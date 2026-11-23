--!strict
-- Stores player settings sent from the client. Settings are cosmetic, except AutoShatter, which the Auto Shatter
-- loop in CrystalService reads (and which only pass owners can switch on). RemoteService has already validated
-- each argument against Net/Remotes.

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)

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

-- SetSetting(name, on): RemoteService has checked name is "AutoShatter" or "Music" and on is a boolean.
-- AutoShatter is accepted only from owners of the Auto Shatter pass (batch 5); the server loop also re-checks the
-- pass before every run, so a stored true does nothing without it.
local function onSetSetting(player: Player, name: string, on: boolean)
	if name == "AutoShatter" and not PassService:Owns(player, "AutoShatter") then
		return
	end
	local data = DataService:GetData(player)
	if data == nil or data.Settings[name] == on then
		return
	end
	data.Settings[name] = on
	DataService:SyncState(player)
end

function SettingsService:Init()
	RemoteService:On("SetBrightness", onSetBrightness)
	RemoteService:On("SetSetting", onSetSetting)
end

function SettingsService:Start() end

return SettingsService
