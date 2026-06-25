local Class = require("BaseClass")

local NeedResolver = Class("NeedResolver")

function NeedResolver:Ctor(config)
    self.config = config
end

function NeedResolver:get_resolver_type(need)
    return need and need.resolver or "equipment"
end

function NeedResolver:is_equipment_need(need)
    return self:get_resolver_type(need) == "equipment"
end

function NeedResolver:item_matches_need(item, need)
    if not (item and item.def and need) then
        return false
    end

    if self:is_equipment_need(need) then
        return item.def.item_key == need.item_key
    end

    return false
end

function NeedResolver:get_spawnable_equipment_needs()
    local result = {}
    local needs = self.config.needs
    for index = 1, #needs do
        local need = needs[index]
        if self:is_equipment_need(need) and need.item_key then
            result[#result + 1] = need
        end
    end
    return result
end

function NeedResolver:get_match_text(need, item)
    if need and need.matched_text then
        return need.matched_text
    end
    if item and item.def then
        return item.def.action_text
    end
    return "去满足需求"
end

function NeedResolver:get_satisfied_text(need, item)
    if need and need.satisfied_text then
        return need.satisfied_text
    end
    if item and item.def then
        return item.def.action_text
    end
    return "满足了"
end

return NeedResolver
