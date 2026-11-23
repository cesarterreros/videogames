--!strict
-- Pure rewarded-video-ad caps: per-placement daily caps, one daily total, and the cooldown
-- between two ads. `today` is a "YYYY-MM-DD" UTC string and every timestamp is passed in,
-- so nothing here reads the clock, calls an API or mutates its inputs.

local AdCaps = {}

export type AdCounts = {
	Date: string,
	FinishNow: number,
	Luck: number,
	CoinPouch: number,
}

export type AdsConfig = {
	CooldownSeconds: number,
	DailyTotal: number,
	Caps: { [string]: number },
}

-- The three placements the stored counts carry, in the shipping config's cap order.
local PLACEMENTS = { "FinishNow", "Luck", "CoinPouch" }

-- One placement's count; a missing or non-number value counts as 0.
local function countOf(adCounts: AdCounts, placement: string): number
	local value = (adCounts :: any)[placement]
	if type(value) == "number" then
		return value
	end
	return 0
end

-- Counts that belong to `today`: a copy when the stored counts are already today's,
-- otherwise a fresh all-zero table (a new day resets every placement).
function AdCaps.countsFor(adCounts: AdCounts, today: string): AdCounts
	if adCounts.Date ~= today then
		return { Date = today, FinishNow = 0, Luck = 0, CoinPouch = 0 }
	end
	return {
		Date = today,
		FinishNow = countOf(adCounts, "FinishNow"),
		Luck = countOf(adCounts, "Luck"),
		CoinPouch = countOf(adCounts, "CoinPouch"),
	}
end

-- Ads watched today across every placement.
function AdCaps.total(adCounts: AdCounts, today: string): number
	local counts = AdCaps.countsFor(adCounts, today)
	return counts.FinishNow + counts.Luck + counts.CoinPouch
end

-- Whether an ad may be shown now. Checks run in a fixed order and the first failure wins:
-- unknown placement, that placement's cap, the daily total, then the cooldown (`lastAdAt` 0 never cooldown).
function AdCaps.check(
	adCounts: AdCounts,
	today: string,
	placement: string,
	now: number,
	lastAdAt: number,
	cfg: AdsConfig
): (boolean, string?)
	local cap = cfg.Caps[placement]
	if cap == nil then
		return false, "Placement"
	end

	local counts = AdCaps.countsFor(adCounts, today)
	if countOf(counts, placement) >= cap then
		return false, "PlacementCap"
	end

	if counts.FinishNow + counts.Luck + counts.CoinPouch >= cfg.DailyTotal then
		return false, "DailyCap"
	end

	if lastAdAt > 0 and now - lastAdAt < cfg.CooldownSeconds then
		return false, "Cooldown"
	end

	return true, nil
end

-- Seconds still to wait before the next ad; 0 when no ad has been watched yet or the wait is over.
function AdCaps.cooldownLeft(now: number, lastAdAt: number, cfg: AdsConfig): number
	if lastAdAt <= 0 then
		return 0
	end
	return math.max(0, cfg.CooldownSeconds - (now - lastAdAt))
end

-- Counts with one more ad recorded for `placement`, on today's date. An unknown placement
-- leaves the counts as they are.
function AdCaps.recordRequest(adCounts: AdCounts, today: string, placement: string): AdCounts
	local counts = AdCaps.countsFor(adCounts, today)
	for _, key in PLACEMENTS do
		if key == placement then
			(counts :: any)[placement] = countOf(counts, placement) + 1
			break
		end
	end
	return counts
end

return AdCaps
