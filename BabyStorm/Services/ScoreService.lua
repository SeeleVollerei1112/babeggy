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

---@param role Role|nil
function ScoreService:award_satisfied(role)
    local reward = self.config.scoring.satisfy_score
    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.satisfied_count = session.satisfied_count + 1
        session.score_awarded = session.score_awarded + reward
    end

    if role and role.add_score then
        role.add_score(reward)
        if role.show_tips then
            role.show_tips("宝宝满足 +" .. tostring(reward), 2.0)
        end
    elseif GlobalAPI and GlobalAPI.show_tips then
        GlobalAPI.show_tips("宝宝满足 +" .. tostring(reward), 2.0)
    end
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

    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.score_awarded = session.score_awarded + bonus
    end

    if role and role.add_score then
        role.add_score(bonus)
        if role.show_tips then
            role.show_tips("顶球 x" .. tostring(catches) .. " +" .. tostring(bonus), 2.0)
        end
    elseif GlobalAPI and GlobalAPI.show_tips then
        GlobalAPI.show_tips("顶球 x" .. tostring(catches) .. " +" .. tostring(bonus), 2.0)
    end
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

    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.score_awarded = session.score_awarded + bonus
    end

    if role and role.add_score then
        role.add_score(bonus)
        if role.show_tips then
            role.show_tips(label .. tostring(bonus), 2.0)
        end
    elseif GlobalAPI and GlobalAPI.show_tips then
        GlobalAPI.show_tips(label .. tostring(bonus), 2.0)
    end
end

---@param role Role|nil
function ScoreService:penalize_wrong(role)
    local penalty = self.config.scoring.wrong_item_penalty
    local session = self.sessions and self.sessions:find(role) or nil
    if session then
        session.wrong_count = session.wrong_count + 1
        session.score_awarded = session.score_awarded - penalty
    end

    if penalty and penalty > 0 and role and role.add_score then
        role.add_score(-penalty)
    end

    if role and role.show_tips then
        role.show_tips("不是想要的", 1.5)
    elseif GlobalAPI and GlobalAPI.show_tips then
        GlobalAPI.show_tips("不是想要的", 1.5)
    end
end

return ScoreService
