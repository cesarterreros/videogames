--!strict
-- Stores player settings sent from the client. Settings are cosmetic: the server only saves them and never
-- reads them for game rules. RemoteService has already validated each argument against Net/Remotes.

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)

local SettingsService = {}

-- level is already one of "Dark" | "Normal" | "Bright" (enum-checked by RemoteService).
local function onSetBrightness(player: Player, level: string)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	if data.Settings.Brightness == level then
		return
	end
	data.Settings.Brightness = level
	DataService:SyncState(player)
end

function SettingsService:Init()
	RemoteService:On("SetBrightness", onSetBrightness)
end

function SettingsService:Start() end

return SettingsService
