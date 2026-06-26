local Class = require("BaseClass")

---@class DifficultyService
---@field config BabyStormConfig
---@field view_model GameViewModel|nil
---@field satisfied_count integer
---@field chaos_level integer
local DifficultyService = Class("DifficultyService")

---@param config BabyStormConfig
---@param game_view_model GameViewModel|nil
function DifficultyService:Ctor(config, game_view_model)
    self.config = config
    self.view_model = game_view_model
    self.satisfied_count = 0
    self.chaos_level = 1
    if self.view_model then
        self.view_model:set_chaos_level(self.chaos_level)
        self.view_model:set_satisfied_count(self.satisfied_count)
    end
end

---@param agent BabyAgent
function DifficultyService:on_baby_satisfied(agent)
    self.satisfied_count = self.satisfied_count + 1

    local step = self.config.difficulty.satisfy_per_chaos_level
    if step and step > 0 then
        local next_level = math.floor(self.satisfied_count / step) + 1
        if next_level > self.config.difficulty.max_chaos_level then
            next_level = self.config.difficulty.max_chaos_level
        end
        self.chaos_level = next_level
    end

    if self.view_model then
        self.view_model:set_chaos_level(self.chaos_level)
        self.view_model:set_satisfied_count(self.satisfied_count)
    end
end

---@return integer
function DifficultyService:get_chaos_level()
    return self.chaos_level
end

return DifficultyService
