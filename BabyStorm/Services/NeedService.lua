local Class = require("BaseClass")
local RandomBag = require("Util.RandomBag")

local NeedService = Class("NeedService")

function NeedService:Ctor(config)
    self.config = config
    self._bag = RandomBag.New(config.needs)
end

function NeedService:take()
    return self._bag:take()
end

function NeedService:all()
    return self.config.needs
end

return NeedService
