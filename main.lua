local BabyMvp = require("BabyMvp")

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    BabyMvp.start()
end)
