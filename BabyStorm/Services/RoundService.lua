local Class = require("BaseClass")

local RoundService = Class("RoundService")

function RoundService:Ctor(config, triggers, sessions, game_view_model)
    self.config = config
    self.triggers = triggers
    self.sessions = sessions
    self.view_model = game_view_model
    self.elapsed_seconds = 0
    self.remaining_seconds = config.round.duration_seconds
    self.running = false
end

function RoundService:start()
    if self.running then
        return
    end

    self.running = true
    self:_sync_view_model()
    self.triggers:global({ EVENT.REPEAT_TIMEOUT, 1.0 }, function()
        self:on_second_tick()
    end)
end

function RoundService:on_second_tick()
    if not self.running then
        return
    end

    self.elapsed_seconds = self.elapsed_seconds + 1
    if self.remaining_seconds > 0 then
        self.remaining_seconds = self.remaining_seconds - 1
    end

    if self.sessions then
        self.sessions:sync_all()
    end
    self:_sync_view_model()
end

function RoundService:_sync_view_model()
    if not self.view_model then
        return
    end

    self.view_model:set_elapsed_seconds(self.elapsed_seconds)
    self.view_model:set_remaining_seconds(self.remaining_seconds)
    if self.sessions then
        self.view_model:set_player_count(self.sessions:count())
    end
end

function RoundService:stop()
    self.running = false
end

return RoundService
