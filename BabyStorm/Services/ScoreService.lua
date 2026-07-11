local Class = require("BaseClass")

---@class ScoreService
---@field config BabyStormConfig
---@field sessions PlayerSessionRegistry|nil
local ScoreService = Class("ScoreService")

---@param config BabyStormConfig
---@param sessions PlayerSessionRegistry|nil
function ScoreService:Ctor(config, sessions)
    self.config = config
    self.sessions = sessions
end

-- 记分共用入口：session 记分（无条件）+ role 加分 + tips（role 有则 role.show_tips，
-- 否则 GlobalAPI.show_tips 全局兜底）。role 判空是正常路径（没有归属玩家，如独自满足）。
-- role_delta 缺省等于 session_delta；显式传 0 可以让 session 扣分但不影响 role 分数
-- （penalize_wrong 的 penalty<=0 分支需要这个语义）。
---@param role Role|nil
---@param session_delta number
---@param tip_text string
---@param tip_duration Fixed
---@param role_delta number|nil
function ScoreService:_award(role, session_delta, tip_text, tip_duration, role_delta)
    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.score_awarded = session.score_awarded + session_delta
    end

    local delta = role_delta
    if delta == nil then
        delta = session_delta
    end
    if role and delta ~= 0 then
        role.add_score(delta)
    end

    if role then
        role.show_tips(tip_text, tip_duration)
    else
        GlobalAPI.show_tips(tip_text, tip_duration)
    end
end

---@param role Role|nil
function ScoreService:award_satisfied(role)
    local reward = self.config.scoring.satisfy_score
    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.satisfied_count = session.satisfied_count + 1
    end
    self:_award(role, reward, "宝宝满足 +" .. tostring(reward), 2.0)
end

---顶球玩法奖励：在基础满足分之外，按成功顶球次数追加奖励（接的越多分越多）。
---@param role Role|nil
---@param catches integer
function ScoreService:award_ball_bonus(role, catches)
    local per = self.config.scoring.ball_catch_score or 0
    local bonus = per * (catches or 0)
    if bonus <= 0 then
        return
    end
    self:_award(role, bonus, "顶球 x" .. tostring(catches) .. " +" .. tostring(bonus), 2.0)
end

---猜拳玩法额外加分：基础满足分之外，按落地判出的“玩家视角”胜负分档追加
---（win/draw/lose 对应 rps_win_score/rps_draw_score/rps_lose_score）。
---outcome 为 nil（未响应的独自满足、或没干净落面无法判胜负）时不调用本函数。
---@param role Role|nil
---@param outcome "win"|"draw"|"lose"
function ScoreService:award_rps_result(role, outcome)
    local scoring = self.config.scoring
    local bonus, label
    if outcome == "win" then
        bonus, label = scoring.rps_win_score or 0, "猜拳赢了 +"
    elseif outcome == "draw" then
        bonus, label = scoring.rps_draw_score or 0, "猜拳平局 +"
    else
        bonus, label = scoring.rps_lose_score or 0, "猜拳输了 +"
    end
    if bonus <= 0 then
        return
    end
    self:_award(role, bonus, label .. tostring(bonus), 2.0)
end

---@param role Role|nil
function ScoreService:penalize_wrong(role)
    local penalty = self.config.scoring.wrong_item_penalty
    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.wrong_count = session.wrong_count + 1
    end
    -- session.score_awarded 无条件扣，role 分数只在 penalty>0 时才扣（role_delta=0 时跳过），
    -- tips 无条件发——塌缩前的原语义，三者不对齐，务必保留。
    local role_delta = (penalty and penalty > 0) and -penalty or 0
    self:_award(role, -penalty, "不是想要的", 1.5, role_delta)
end

return ScoreService
