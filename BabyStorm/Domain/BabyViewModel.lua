local Class = require("BaseClass")
local ViewModelBase = require("MVVM.ViewModelBase")

local BabyViewModel = Class("BabyViewModel", ViewModelBase)

BabyViewModel.Field = {
    State = "State",
    StatusText = "StatusText",
    NeedId = "NeedId",
    NeedText = "NeedText",
    Busy = "Busy",
    Stress = "Stress",
}

function BabyViewModel:Ctor()
    BabyViewModel.super.Ctor(self)

    local field = BabyViewModel.Field
    self:set_property_silently(field.State, 0)
    self:set_property_silently(field.StatusText, "")
    self:set_property_silently(field.NeedId, "")
    self:set_property_silently(field.NeedText, "")
    self:set_property_silently(field.Busy, false)
    self:set_property_silently(field.Stress, 0)
end

function BabyViewModel:set_state(value)
    return self:set_property(self.Field.State, value)
end

function BabyViewModel:get_state()
    return self:get_property(self.Field.State)
end

function BabyViewModel:set_status_text(value)
    return self:set_property(self.Field.StatusText, value or "")
end

function BabyViewModel:get_status_text()
    return self:get_property(self.Field.StatusText)
end

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

function BabyViewModel:get_need_id()
    return self:get_property(self.Field.NeedId)
end

function BabyViewModel:get_need_text()
    return self:get_property(self.Field.NeedText)
end

function BabyViewModel:set_busy(value)
    return self:set_property(self.Field.Busy, value and true or false)
end

function BabyViewModel:is_busy()
    return self:get_property(self.Field.Busy)
end

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
