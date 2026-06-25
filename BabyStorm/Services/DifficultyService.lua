local Class = require("BaseClass")

local DifficultyService = Class("DifficultyService")

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

function DifficultyService:get_chaos_level()
    return self.chaos_level
end

return DifficultyService
