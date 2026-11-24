--!strict
-- Graphics profiles: how much of the crystal look a client gets, chosen from its graphics quality level.
-- From the batch 2 phone proof (57-60 FPS with 78 crystals, no fallback needed), Full is today's look:
-- a light on every Epic/Legendary, glass shells on every prism and full emitter rates. Low is the
-- automatic fallback at graphics levels 1-3: the shells stay (they are what makes a crystal read as a
-- crystal), but fewer crystals earn a light and particles are halved. Automatic (level 0) keeps Full,
-- because the engine already lowers its own rendering by itself.

export type Profile = {
	LightsMinTier: number,
	MutationLights: boolean,
	ParticleRate: number,
	GlassShell: boolean,
}

local FULL = "Full"
local LOW = "Low"

local Graphics = {}

-- Profile per name. Both are complete: a client never has to patch a profile together.
Graphics.Profiles = {
	Full = { LightsMinTier = 7, MutationLights = true, ParticleRate = 1, GlassShell = true } :: Profile,
	Low = { LightsMinTier = 9, MutationLights = true, ParticleRate = 0.5, GlassShell = true } :: Profile,
} :: { [string]: Profile }

-- Highest SavedQualityLevel that still counts as "Low": levels 1-3 are the weak-device bracket.
Graphics.LowMaxQualityLevel = 3

-- Profile name for a UserGameSettings.SavedQualityLevel value: 0 = Automatic -> Full,
-- 1..LowMaxQualityLevel -> Low, anything else (4..10, non-numbers, NaN) -> Full.
function Graphics.profileName(savedLevel: any): string
	if typeof(savedLevel) ~= "number" or savedLevel ~= savedLevel then
		return FULL
	end
	if savedLevel >= 1 and savedLevel <= Graphics.LowMaxQualityLevel then
		return LOW
	end
	return FULL
end

-- The profile table for a SavedQualityLevel value.
function Graphics.profile(savedLevel: any): Profile
	return Graphics.Profiles[Graphics.profileName(savedLevel)]
end

return Graphics
