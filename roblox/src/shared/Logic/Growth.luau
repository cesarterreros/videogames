--!strict
-- Pure growth math for planted crystals: grow time, progress, readiness, overgrowth and shatter payout.
-- The caller passes the current time; nothing in here touches Roblox APIs.

local Growth = {}

-- Seconds a plant needs to grow: the lamp level trims the base time, a speed multiplier scales it.
-- Never returns less than 1 s so a plant always takes at least one tick.
function Growth.growSeconds(baseSeconds: number, lampLevel: number, lampStep: number, speedMult: number?): number
	return math.max(1, baseSeconds * (1 - lampLevel * lampStep) * (speedMult or 1))
end

-- Fraction grown so far, in 0..1. An empty or inverted window (readyAt <= plantedAt) counts as complete.
function Growth.progress(now: number, plantedAt: number, readyAt: number): number
	if readyAt <= plantedAt then
		return 1
	end
	return math.clamp((now - plantedAt) / (readyAt - plantedAt), 0, 1)
end

-- True once the grow window has elapsed.
function Growth.isReady(now: number, readyAt: number): boolean
	return now >= readyAt
end

-- Extra value multiplier earned by leaving a ripe plant in the ground: it climbs continuously per hour
-- and stops at `cap`. Always 0 before the plant is ready.
function Growth.overgrowth(now: number, readyAt: number, perHour: number, cap: number): number
	return math.clamp((now - readyAt) / 3600 * perHour, 0, cap)
end

-- Coins and carats paid out when a grown crystal is shattered.
-- The tiny `1e-9` nudge keeps float products such as 17.999999999 from flooring down to 17.
function Growth.shatterValue(
	baseValue: number,
	baseCarats: number,
	sizeRoll: number,
	mutationMult: number,
	overgrowth: number,
	coinMult: number?
): (number, number)
	local coins = math.floor(baseValue * sizeRoll * mutationMult * (1 + overgrowth) * (coinMult or 1) + 1e-9)
	local carats = baseCarats * sizeRoll * (1 + overgrowth)
	return coins, carats
end

return Growth
