local Class = require("BaseClass")
local ViewModelBase = require("MVVM.ViewModelBase")

---@class GameViewModel: ViewModelBase
---@field Field table<string, string>
local GameViewModel = Class("BabyStormGameViewModel", ViewModelBase)

---@type table<string, string>
GameViewModel.Field = {
    ElapsedSeconds = "ElapsedSeconds",
    RemainingSeconds = "RemainingSeconds",
    ChaosLevel = "ChaosLevel",
    SatisfiedCount = "SatisfiedCount",
    ActiveBabyCount = "ActiveBabyCount",
    PlayerCount = "PlayerCount",
}

function GameViewModel:Ctor()
    GameViewModel.super.Ctor(self)
    local field = GameViewModel.Field
    self:set_property_silently(field.ElapsedSeconds, 0)
    self:set_property_silently(field.RemainingSeconds, 0)
    self:set_property_silently(field.ChaosLevel, 1)
    self:set_property_silently(field.SatisfiedCount, 0)
    self:set_property_silently(field.ActiveBabyCount, 0)
    self:set_property_silently(field.PlayerCount, 0)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_elapsed_seconds(value)
    return self:set_property(self.Field.ElapsedSeconds, value or 0)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_remaining_seconds(value)
    return self:set_property(self.Field.RemainingSeconds, value or 0)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_chaos_level(value)
    return self:set_property(self.Field.ChaosLevel, value or 1)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_satisfied_count(value)
    return self:set_property(self.Field.SatisfiedCount, value or 0)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_active_baby_count(value)
    return self:set_property(self.Field.ActiveBabyCount, value or 0)
end

---@param value integer|nil
---@return boolean
function GameViewModel:set_player_count(value)
    return self:set_property(self.Field.PlayerCount, value or 0)
end

return GameViewModel
