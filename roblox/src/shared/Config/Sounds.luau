--!strict
-- Sound asset IDs and playback settings. Pure data. An ID of 0 is silent, so the game works before IDs are
-- filled in. Use only audio from the Creator Store that Roblox publishes (licensed for experiences), never
-- uploaded copyrighted music.

export type SoundsConfig = {
	Ids: { [string]: number },
	MusicVolume: number,
	EffectsVolume: number,
	ShatterPitchStep: number,
}

local Sounds: SoundsConfig = {
	Ids = {
		Shatter = 12222005, -- "glassbreak.wav" (Roblox), 1.58 s; pitch rises with the seed tier
		Coin = 127645268874265, -- "CoinTransfer_01" (Roblox), 1.66 s
		Ready = 15675085146, -- "Roblox_UI_Indicator" (Roblox), 3.37 s
		Mutation = 15675043410, -- "Roblox_UI_Tonal_Stinger" (Roblox), 1.47 s
		NewBest = 15675016548, -- "Roblox_UI_Piano_Hello" (Roblox), 4.04 s
		Click = 15675032796, -- "Roblox_UI_Small_Click" (Roblox), 0.13 s
		Music = 15675069601, -- "Roblox_UI_Loop_Calm_Music" (Roblox), 95.5 s loop
	},
	MusicVolume = 0.3,
	EffectsVolume = 0.6,
	-- Shatter PlaybackSpeed = 1 + ShatterPitchStep x (tier - 1).
	ShatterPitchStep = 0.05,
}

return Sounds
