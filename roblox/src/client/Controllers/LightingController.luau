--!strict
-- Cave brightness presets applied to this client's own Lighting. Cosmetic and client-only: the server only stores the choice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LightingService = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.Lighting)
local StateController = require(script.Parent.StateController)

type RGB = { number }

type Preset = {
	Ambient: RGB,
	OutdoorAmbient: RGB,
	Brightness: number,
	ExposureCompensation: number,
}

local presets: { [string]: Preset } = LightingConfig.Presets

local LightingController = {}

-- The level name last written to Lighting (nil = nothing written yet), and the clock time until which
-- incoming StateSync snapshots are ignored because a tap is still settling.
local lastApplied: string? = nil
local holdUntil: number = 0

-- Writes one preset's four properties to Lighting. Unknown level names are ignored.
function LightingController.apply(level: string)
	local preset: Preset? = presets[level]
	if preset == nil then
		return
	end

	LightingService.Ambient = Color3.fromRGB(preset.Ambient[1], preset.Ambient[2], preset.Ambient[3])
	LightingService.OutdoorAmbient =
		Color3.fromRGB(preset.OutdoorAmbient[1], preset.OutdoorAmbient[2], preset.OutdoorAmbient[3])
	LightingService.Brightness = preset.Brightness
	LightingService.ExposureCompensation = preset.ExposureCompensation
	lastApplied = level
end

-- Applies a level picked by the player and briefly ignores snapshots for earlier taps so fast tapping doesn't flicker.
function LightingController.applyFromTap(level: string)
	LightingController.apply(level)
	if presets[level] ~= nil then
		holdUntil = os.clock() + 1.5
	end
end

-- The level currently on screen.
function LightingController.current(): string
	return lastApplied or LightingConfig.Default
end

-- Nothing to set up. Must not yield.
function LightingController:Init() end

-- Follows the stored brightness level, but only writes when it differs from what is already applied.
function LightingController:Start()
	local function onState(data: any)
		if typeof(data) ~= "table" then
			return
		end

		local snapshot: { [string]: any } = data
		local settings = snapshot.Settings
		if typeof(settings) ~= "table" then
			return
		end

		local level: any = settings.Brightness
		if type(level) ~= "string" then
			return
		end

		if os.clock() < holdUntil then
			return
		end

		if level ~= lastApplied then
			LightingController.apply(level)
		end
	end

	StateController.Changed:Connect(onState)

	local existing = StateController:Get()
	if existing ~= nil then
		onState(existing)
	end
end

return LightingController
