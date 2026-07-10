local Class = require("BaseClass")
local ViewModelBase = require("MVVM.ViewModelBase")

---@class BabyViewModel: ViewModelBase
---@field Field table<string, string>
local BabyViewModel = Class("BabyViewModel", ViewModelBase)

---@type table<string, string>
BabyViewModel.Field = {
    State = "State",
    StatusText = "StatusText",
    NeedId = "NeedId",
    NeedText = "NeedText",
    Stress = "Stress",
}

function BabyViewModel:Ctor()
    BabyViewModel.super.Ctor(self)

    local field = BabyViewModel.Field
    self:set_property_silently(field.State, 0)
    self:set_property_silently(field.StatusText, "")
    self:set_property_silently(field.NeedId, "")
    self:set_property_silently(field.NeedText, "")
    self:set_property_silently(field.Stress, 0)
end

---@param value integer
---@return boolean
function BabyViewModel:set_state(value)
    return self:set_property(self.Field.State, value)
end

---@return integer
function BabyViewModel:get_state()
    return self:get_property(self.Field.State)
end

---@param value string|nil
---@return boolean
function BabyViewModel:set_status_text(value)
    return self:set_property(self.Field.StatusText, value or "")
end

---@return string
function BabyViewModel:get_status_text()
    return self:get_property(self.Field.StatusText)
end

---@param need BabyNeedDef|nil
function BabyViewModel:set_need(need)
    if need then
        self:begin_batch()
        self:set_property(self.Field.NeedId, need.id)
        self:set_property(self.Field.NeedText, need.need_text)
        self:end_batch()
    else
        self:begin_batch()
        self:set_property(self.Field.NeedId, "")
        self:set_property(self.Field.NeedText, "")
        self:end_batch()
    end
end

---@return string
function BabyViewModel:get_need_id()
    return self:get_property(self.Field.NeedId)
end

---@return string
function BabyViewModel:get_need_text()
    return self:get_property(self.Field.NeedText)
end

---@param delta integer|nil
---@return boolean
function BabyViewModel:add_stress(delta)
    local value = self:get_property(self.Field.Stress) + (delta or 0)
    if value < 0 then
        value = 0
    end
    return self:set_property(self.Field.Stress, value)
end

function BabyViewModel:clear()
    BabyViewModel.super.clear(self)
end

return BabyViewModel
