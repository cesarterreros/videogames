--!strict
-- Cave brightness levels: the Lighting values for each level a player can pick, the tap order and the default.
-- Pure data. Colours are { r, g, b } tables (0-255) because Color3 doesn't exist under Lune; the game converts them
-- with Color3.fromRGB. To tune live: in a Studio Play, edit Lighting on the client in Properties, then copy the numbers here.

export type RGB = { number }

-- The atmosphere look shared by every brightness level: the moody fog haze, the slight colour grade and the bloom.
-- The Atmosphere instance replaces the old fog (Roblox hides the Fog properties while Lighting contains an
-- Atmosphere), so the brightness presets still change only Ambient/OutdoorAmbient/Brightness/ExposureCompensation.
export type EffectsConfig = {
	ClockTime: number,
	Atmosphere: { Density: number, Offset: number, Color: RGB, Decay: RGB, Glare: number, Haze: number },
	ColorCorrection: { Saturation: number, Contrast: number, Brightness: number },
	Bloom: { Intensity: number, Size: number, Threshold: number },
}

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
	Effects: EffectsConfig,
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
	-- Shared by every brightness level: the same night sky, haze, colour grade and bloom whatever the level.
	Effects = {
		-- Midnight: no sun, so only the neon crystals and the effects light the caves.
		ClockTime = 0,
		-- Blue-purple haze replacing the old fog. Density 0.35 is thick enough to hide the world's far edge.
		Atmosphere = {
			Density = 0.35,
			Offset = 0,
			Color = { 80, 70, 140 },
			Decay = { 40, 30, 80 },
			Glare = 0,
			Haze = 1,
		},
		-- A gentle grade: a little more colour and contrast, no brightness change.
		ColorCorrection = {
			Saturation = 0.1,
			Contrast = 0.05,
			Brightness = 0,
		},
		-- Soft halo around the neon without blowing out the rock.
		Bloom = {
			Intensity = 0.8,
			Size = 24,
			Threshold = 1.1,
		},
	},
}

return Lighting
