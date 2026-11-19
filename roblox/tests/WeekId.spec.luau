-- WeekId.spec.luau - unit tests for the pure ISO week-id helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local WeekId = require("../src/shared/Logic/WeekId")

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

-- Unix time of a UTC wall-clock instant, built with arithmetic only (never os.time).
local function utc(y: number, m: number, d: number, h: number?, min: number?, sec: number?): number
	return daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (min or 0) * 60 + (sec or 0)
end

return function(test)
	test("fromUnix: mid-year Wednesday", function()
		expect(WeekId.fromUnix(utc(2026, 11, 18))):toBe("2026W47")
	end)

	test("fromUnix: 53-week year near new year", function()
		expect(WeekId.fromUnix(utc(2026, 12, 28))):toBe("2026W53")
		expect(WeekId.fromUnix(utc(2026, 12, 31))):toBe("2026W53")
		expect(WeekId.fromUnix(utc(2027, 1, 1))):toBe("2026W53")
		expect(WeekId.fromUnix(utc(2027, 1, 4))):toBe("2027W01")
	end)

	test("fromUnix: late December belonging to next ISO year", function()
		expect(WeekId.fromUnix(utc(2024, 12, 30))):toBe("2025W01")
	end)

	test("fromUnix: Sunday belonging to previous ISO year", function()
		expect(WeekId.fromUnix(utc(2021, 1, 3))):toBe("2020W53")
	end)

	test("fromUnix: same week across Monday 00:00 to Sunday 23:59:59", function()
		expect(WeekId.fromUnix(utc(2026, 11, 16, 0, 0, 0))):toBe("2026W47")
		expect(WeekId.fromUnix(utc(2026, 11, 18, 12, 0, 0))):toBe("2026W47")
		expect(WeekId.fromUnix(utc(2026, 11, 22, 23, 59, 59))):toBe("2026W47")
	end)

	test("fromUnix: next Monday starts the next week", function()
		expect(WeekId.fromUnix(utc(2026, 11, 23, 0, 0, 0))):toBe("2026W48")
	end)

	test("fromUnix: weekday mapping for every day of one week", function()
		for day = 16, 22 do
			expect(WeekId.fromUnix(utc(2026, 11, day, 12))):toBe("2026W47")
		end
	end)

	test("dateString: UTC YYYY-MM-DD", function()
		expect(WeekId.dateString(utc(2026, 11, 18, 15))):toBe("2026-11-18")
		expect(WeekId.dateString(utc(2026, 11, 18, 23, 59, 59))):toBe("2026-11-18")
		expect(WeekId.dateString(utc(2027, 1, 1, 0, 0, 0))):toBe("2027-01-01")
		expect(WeekId.dateString(utc(2024, 2, 29, 6))):toBe("2024-02-29")
	end)

	test("weekStartUnix: Monday 00:00 UTC of the ISO week", function()
		expect(WeekId.weekStartUnix(utc(2026, 11, 18, 15))):toBe(utc(2026, 11, 16))
		expect(WeekId.weekStartUnix(utc(2026, 11, 16, 0, 0, 0))):toBe(utc(2026, 11, 16))
		expect(WeekId.weekStartUnix(utc(2026, 11, 22, 23, 59, 59))):toBe(utc(2026, 11, 16))
		expect(WeekId.weekStartUnix(utc(2027, 1, 1, 9))):toBe(utc(2026, 12, 28))
	end)

	test("weekStartUnix: always a multiple of a day and at or before the input", function()
		local t = utc(2026, 11, 19, 7, 30, 15)
		local start = WeekId.weekStartUnix(t)
		expect(start % 86400):toBe(0)
		expect(start <= t):toBeTruthy()
		expect(t - start < 7 * 86400):toBeTruthy()
	end)

	test("WeekId module contains no require", function()
		local source = fs.readFile("src/shared/Logic/WeekId.luau")
		expect(string.find(source, "require", 1, true)):toBeNil()
	end)
end
