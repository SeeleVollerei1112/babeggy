local Class = require("BaseClass")
local RandomBag = require("Util.RandomBag")

---@class NeedService
---@field config BabyStormConfig
---@field _bag RandomBag
local NeedService = Class("NeedService")

---@param config BabyStormConfig
function NeedService:Ctor(config)
    self.config = config
    self._bag = RandomBag.New(config.needs)
end

---@return BabyNeedDef|nil
function NeedService:take()
    return self._bag:take()
end

---@return BabyNeedDef[]
function NeedService:all()
    return self.config.needs
end

return NeedService
