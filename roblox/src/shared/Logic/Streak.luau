--!strict
-- Pure daily-streak math: decides whether today's claim extends the streak and which day number it lands on.
-- Dates arrive as "YYYY-MM-DD" strings from the caller, so nothing here reads the clock.

-- Shape of a saved streak. Day 0 with an empty LastClaimDate means "never claimed".
export type StreakData = {
	Day: number,
	LastClaimDate: string,
}

local DEFAULT_CYCLE = 7

local Streak = {}

-- Resolves a claim for today. Returns (claimed, newStreak, day); a refused claim gives false, nil, nil.
-- The input table is never modified: a successful claim hands back a brand new one.
function Streak.claim(
	streak: StreakData,
	today: string,
	yesterday: string,
	cycle: number?
): (boolean, { Day: number, LastClaimDate: string }?, number?)
	local days = cycle or DEFAULT_CYCLE
	if streak.LastClaimDate == today then
		return false, nil, nil
	end

	local day: number
	if streak.LastClaimDate == yesterday and streak.Day >= 1 then
		day = streak.Day + 1
		-- A full cycle wraps around to day 1 instead of growing forever.
		if day > days then
			day = 1
		end
	else
		day = 1
	end

	return true, { Day = day, LastClaimDate = today }, day
end

return Streak
