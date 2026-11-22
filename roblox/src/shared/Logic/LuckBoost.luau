--!strict
-- Pure luck-boost math: banked minutes from the paid Luck Boost, its countdown, and the
-- mutation chance multiplier it adds on top of a surge. Every timestamp comes in as an
-- argument, so the module has no clock, no Roblox APIs and no side effects.

local LuckBoost = {}

-- Seconds in one minute, used for every config value that arrives in minutes.
local MINUTE = 60

-- New end time after buying `minutes` of boost: stacking starts at the later of now and the
-- current end, and the bank is never allowed to reach further than `maxBankMinutes` past now.
function LuckBoost.extend(endsAt: number, now: number, minutes: number, maxBankMinutes: number): number
	return math.min(math.max(now, endsAt) + minutes * MINUTE, now + maxBankMinutes * MINUTE)
end

-- True while the boost still has time left at `now`.
function LuckBoost.isActive(now: number, endsAt: number): boolean
	return now < endsAt
end

-- Seconds remaining on the boost, never below zero once it has run out.
function LuckBoost.secondsLeft(now: number, endsAt: number): number
	return math.max(0, endsAt - now)
end

-- Mutation chance multiplier from the boost and an optional surge, capped at `maxTotal`.
-- With the shipping config (luck 2, surge 2, cap 3): nothing gives 1, either one alone gives 2, both give 3.
function LuckBoost.chanceMult(
	now: number,
	endsAt: number,
	surgeActive: boolean,
	luckMult: number,
	surgeMult: number,
	maxTotal: number
): number
	local luck = if LuckBoost.isActive(now, endsAt) then luckMult else 1
	local surge = if surgeActive then surgeMult else 1
	return math.min(maxTotal, luck * surge)
end

-- Whether the free-luck ad may be offered: only once at most `maxLeftSeconds` of boost remain.
function LuckBoost.canWatchAd(now: number, endsAt: number, maxLeftSeconds: number): boolean
	return LuckBoost.secondsLeft(now, endsAt) <= maxLeftSeconds
end

return LuckBoost
