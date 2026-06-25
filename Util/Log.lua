local Log = {}

Log.prefix = "[BabyStorm]"

function Log.info(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    LuaAPI.log(Log.prefix .. " " .. table.concat(parts, " "), 0)
end

function Log.warn(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    LuaAPI.log(Log.prefix .. " [WARN] " .. table.concat(parts, " "), 0)
end

return Log
