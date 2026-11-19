--!strict
-- ISO-8601 week identifiers for UTC Unix timestamps, using pure arithmetic only.

local WeekId = {}

local SECONDS_PER_DAY = 86400

-- Days since 1970-01-01 for a civil date (Howard Hinnant's days_from_civil).
local function daysFromCivil(y: number, m: number, d: number): number
	local shiftedYear = y - if m <= 2 then 1 else 0
	local era = math.floor(shiftedYear / 400)
	local yearOfEra = shiftedYear - era * 400
	local shiftedMonth = m + if m > 2 then -3 else 9
	local dayOfYear = math.floor((153 * shiftedMonth + 2) / 5) + d - 1
	local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
	return era * 146097 + dayOfEra - 719468
end

-- Civil (year, month, day) for a day count since 1970-01-01 (Howard Hinnant's civil_from_days).
local function civilFromDays(days: number): (number, number, number)
	local shifted = days + 719468
	local era = math.floor(shifted / 146097)
	local dayOfEra = shifted - era * 146097
	local yearOfEra = math.floor(
		(dayOfEra - math.floor(dayOfEra / 1460) + math.floor(dayOfEra / 36524) - math.floor(dayOfEra / 146096)) / 365
	)
	local year = yearOfEra + era * 400
	local dayOfYear = dayOfEra - (365 * yearOfEra + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
	local shiftedMonth = math.floor((5 * dayOfYear + 2) / 153)
	local day = dayOfYear - math.floor((153 * shiftedMonth + 2) / 5) + 1
	local month = shiftedMonth + if shiftedMonth < 10 then 3 else -9
	return year + if month <= 2 then 1 else 0, month, day
end

-- ISO weekday Mon=1..Sun=7 for a day count (1970-01-01 was a Thursday, so Mon=4-3=1).
local function isoWeekday(days: number): number
	return (days + 3) % 7 + 1
end

-- Day count of the Thursday belonging to the ISO week that contains `days`.
local function thursdayOfWeek(days: number): number
	return days + (4 - isoWeekday(days))
end

-- ISO week id such as "2026W47" for the UTC date of Unix time `t`.
function WeekId.fromUnix(t: number): string
	local days = math.floor(t / SECONDS_PER_DAY)
	local thursday = thursdayOfWeek(days)
	local isoYear = select(1, civilFromDays(thursday))
	local week = math.floor((thursday - daysFromCivil(isoYear, 1, 1)) / 7) + 1
	return string.format("%dW%02d", isoYear, week)
end

-- UTC calendar date "YYYY-MM-DD" of Unix time `t`.
function WeekId.dateString(t: number): string
	local year, month, day = civilFromDays(math.floor(t / SECONDS_PER_DAY))
	return string.format("%04d-%02d-%02d", year, month, day)
end

-- Unix time of Monday 00:00 UTC of the ISO week that contains Unix time `t`.
function WeekId.weekStartUnix(t: number): number
	local days = math.floor(t / SECONDS_PER_DAY)
	local monday = days - (isoWeekday(days) - 1)
	return monday * SECONDS_PER_DAY
end

return WeekId
