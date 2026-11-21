--!strict
-- Cave brightness levels: the Lighting values for each level a player can pick, the tap order and the default.
-- Pure data. Colours are { r, g, b } tables (0-255) because Color3 doesn't exist under Lune; the game converts them
-- with Color3.fromRGB. To tune live: in a Studio Play, edit Lighting on the client in Properties, then copy the numbers here.

export type RGB = { number }

export type Preset = {
	Ambient: RGB,
	OutdoorAmbient: RGB,
	Brightness: number,
	ExposureCompensation: number,
}

export type LightingConfig = {
	Levels: { string },
	Presets: { [string]: Preset },
	Default: string,
}

local Lighting: LightingConfig = {
	-- The order the brightness button cycles through.
	Levels = { "Normal", "Bright", "Dark" },
	Presets = {
		-- Near-black caves; the crystals glow strongly. The game's original look.
		Dark = {
			Ambient = { 24, 26, 48 },
			OutdoorAmbient = { 34, 38, 70 },
			Brightness = 1,
			ExposureCompensation = 0,
		},
		-- Pedestals, walls and avatars clearly visible; crystals still glow.
		Normal = {
			Ambient = { 120, 124, 165 },
			OutdoorAmbient = { 130, 136, 180 },
			Brightness = 2,
			ExposureCompensation = 0.6,
		},
		-- Easy to read even on a dim phone screen; the glow is less dramatic.
		Bright = {
			Ambient = { 165, 168, 200 },
			OutdoorAmbient = { 175, 180, 215 },
			Brightness = 2,
			ExposureCompensation = 0.8,
		},
	},
	-- The level everyone gets until they pick another one.
	Default = "Normal",
}

return Lighting
