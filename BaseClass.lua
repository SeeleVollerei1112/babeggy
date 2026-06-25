local setmetatableindex_
setmetatableindex_ = function(t, index)
    local mt = getmetatable(t)
    if not mt then
        mt = {}
    end
    if not mt.__index then
        mt.__index = index
        setmetatable(t, mt)
    elseif mt.__index ~= index then
        setmetatableindex_(mt, index)
    end
end

local function class(class_name, ...)
    local cls = { __cname = class_name, __type = "LuaClass" }
    local supers = { ... }

    for index = 1, #supers do
        local super = supers[index]
        local super_type = type(super)
        if super_type == "function" then
            cls.__create = super
        elseif super_type == "table" then
            cls.__supers = cls.__supers or {}
            cls.__supers[#cls.__supers + 1] = super
            if not cls.super then
                cls.super = super
            end
        end
    end

    cls.__index = cls
    if not cls.__supers or #cls.__supers == 1 then
        setmetatable(cls, { __index = cls.super })
    else
        setmetatable(cls, {
            __index = function(_, key)
                local list = cls.__supers
                for index = 1, #list do
                    local value = list[index][key]
                    if value then
                        return value
                    end
                end
                return nil
            end
        })
    end

    if not cls.Ctor then
        cls.Ctor = function() end
    end

    cls.New = function(...)
        local instance = cls.__create and cls.__create(...) or {}
        setmetatableindex_(instance, cls)
        instance.class = cls
        instance.className = class_name
        instance:Ctor(...)
        return instance
    end

    cls.Create = function(_, ...)
        return cls.New(...)
    end

    return cls
end

return class
