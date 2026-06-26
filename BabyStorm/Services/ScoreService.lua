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
