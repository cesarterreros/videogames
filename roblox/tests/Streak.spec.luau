-- Streak.spec.luau - unit tests for the pure daily-streak helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Streak = require("../src/shared/Logic/Streak")

local TODAY = "2026-11-21"
local YESTERDAY = "2026-11-20"
local TWO_DAYS_AGO = "2026-11-19"

-- A never-claimed streak, so one test can never leak state into the next.
local function freshStreak()
	return { Day = 0, LastClaimDate = "" }
end

return function(test)
	test("claim: the very first claim starts the streak on day 1", function()
		local claimed, next, day = Streak.claim(freshStreak(), TODAY, YESTERDAY)
		expect(claimed):toBe(true)
		expect(next and next.Day):toBe(1)
		expect(next and next.LastClaimDate):toBe(TODAY)
		expect(day):toBe(1)
	end)

	test("claim: claiming yesterday keeps the streak running", function()
		local claimed, next, day = Streak.claim({ Day = 3, LastClaimDate = YESTERDAY }, TODAY, YESTERDAY)
		expect(claimed):toBe(true)
		expect(next and next.Day):toBe(4)
		expect(next and next.LastClaimDate):toBe(TODAY)
		expect(day):toBe(4)
	end)

	test("claim: day 7 claimed yesterday wraps back to day 1", function()
		local claimed, next, day = Streak.claim({ Day = 7, LastClaimDate = YESTERDAY }, TODAY, YESTERDAY)
		expect(claimed):toBe(true)
		expect(next and next.Day):toBe(1)
		expect(day):toBe(1)
	end)

	test("claim: a missed day restarts the streak on day 1", function()
		local claimed, next, day = Streak.claim({ Day = 3, LastClaimDate = TWO_DAYS_AGO }, TODAY, YESTERDAY)
		expect(claimed):toBe(true)
		expect(next and next.Day):toBe(1)
		expect(next and next.LastClaimDate):toBe(TODAY)
		expect(day):toBe(1)
	end)

	test("claim: a second claim on the same day is refused", function()
		local claimed, next, day = Streak.claim({ Day = 3, LastClaimDate = TODAY }, TODAY, YESTERDAY)
		expect(claimed):toBe(false)
		expect(next):toBeNil()
		expect(day):toBeNil()
	end)

	test("claim: the input streak is never modified", function()
		local streak = freshStreak()
		Streak.claim(streak, TODAY, YESTERDAY)
		expect(streak.Day):toBe(0)
		expect(streak.LastClaimDate):toBe("")

		local mid = { Day = 3, LastClaimDate = YESTERDAY }
		local _, next = Streak.claim(mid, TODAY, YESTERDAY)
		expect(mid.Day):toBe(3)
		expect(mid.LastClaimDate):toBe(YESTERDAY)
		expect(next).never:toBe(mid)
	end)

	test("claim: a custom cycle of 3 wraps on the fourth day", function()
		local claimed, next, day = Streak.claim({ Day = 3, LastClaimDate = YESTERDAY }, TODAY, YESTERDAY, 3)
		expect(claimed):toBe(true)
		expect(next and next.Day):toBe(1)
		expect(day):toBe(1)

		local shortClaimed, shortNext = Streak.claim({ Day = 2, LastClaimDate = YESTERDAY }, TODAY, YESTERDAY, 3)
		expect(shortClaimed):toBe(true)
		expect(shortNext and shortNext.Day):toBe(3)
	end)

	test("Streak module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Streak.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
