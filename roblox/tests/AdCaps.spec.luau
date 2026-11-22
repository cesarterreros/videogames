-- AdCaps.spec.luau - unit tests for the pure rewarded-ad cap helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local AdCaps = require("../src/shared/Logic/AdCaps")

-- A fixed UTC second, so every cooldown offset below stays readable.
local NOW = 1800000000

-- The shipping Monetization/Ads config: 60 s cooldown, 9 ads a day,
-- and per-placement caps of FinishNow 5, Luck 3 and CoinPouch 1.
local CFG: AdCaps.AdsConfig = {
	CooldownSeconds = 60,
	DailyTotal = 9,
	Caps = {
		FinishNow = 5,
		Luck = 3,
		CoinPouch = 1,
	},
}

-- Same cooldown and daily total, but no placement is ever the bottleneck: used to prove the
-- daily total refuses an ad on its own.
local CFG2: AdCaps.AdsConfig = {
	CooldownSeconds = 60,
	DailyTotal = 9,
	Caps = {
		FinishNow = 10,
		Luck = 10,
		CoinPouch = 10,
	},
}

-- UTC date strings: the stored counts belong to today unless they carry an older date.
local TODAY = "2027-01-15"
local YESTERDAY = "2027-01-14"

-- A brand new day: nothing watched yet.
local FRESH: AdCaps.AdCounts = { Date = TODAY, FinishNow = 0, Luck = 0, CoinPouch = 0 }

-- Builds today's counts with the given values, for the cap and total cases.
local function counts(finishNow: number, luck: number, coinPouch: number): AdCaps.AdCounts
	return { Date = TODAY, FinishNow = finishNow, Luck = luck, CoinPouch = coinPouch }
end

return function(test)
	test("countsFor: a new date starts from zero", function()
		expect(AdCaps.countsFor({ Date = YESTERDAY, FinishNow = 5, Luck = 3, CoinPouch = 1 }, TODAY)):toEqual(FRESH)
		expect(AdCaps.countsFor(FRESH, TODAY)):toEqual(FRESH)
	end)

	test("countsFor: today's counts are copied, not shared", function()
		local stored = counts(2, 1, 0)
		local copy = AdCaps.countsFor(stored, TODAY)
		expect(copy):toEqual(counts(2, 1, 0))
		expect(copy ~= stored):toBe(true)
	end)

	test("countsFor: missing and non-number counts become 0", function()
		local broken: any = { Date = TODAY, FinishNow = 2, Luck = "many" }
		expect(AdCaps.countsFor(broken, TODAY)):toEqual(counts(2, 0, 0))
	end)

	test("total: adds every placement for today only", function()
		expect(AdCaps.total(FRESH, TODAY)):toBe(0)
		expect(AdCaps.total(counts(4, 3, 1), TODAY)):toBe(8)
		expect(AdCaps.total({ Date = YESTERDAY, FinishNow = 5, Luck = 3, CoinPouch = 1 }, TODAY)):toBe(0)
	end)

	test("check: a fresh day allows every placement", function()
		expect(AdCaps.check(FRESH, TODAY, "FinishNow", NOW, 0, CFG)):toBe(true)
		expect(select(2, AdCaps.check(FRESH, TODAY, "Luck", NOW, 0, CFG))):toBeNil()
		expect(AdCaps.check(FRESH, TODAY, "CoinPouch", NOW, 0, CFG)):toBe(true)
	end)

	test("check: FinishNow is refused at 5 a day, allowed at 4", function()
		local ok, reason = AdCaps.check(counts(5, 0, 0), TODAY, "FinishNow", NOW, 0, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("PlacementCap")
		expect(AdCaps.check(counts(4, 0, 0), TODAY, "FinishNow", NOW, 0, CFG)):toBe(true)
	end)

	test("check: Luck is refused at 3 a day, allowed at 2", function()
		local ok, reason = AdCaps.check(counts(0, 3, 0), TODAY, "Luck", NOW, 0, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("PlacementCap")
		expect(AdCaps.check(counts(0, 2, 0), TODAY, "Luck", NOW, 0, CFG)):toBe(true)
	end)

	test("check: CoinPouch is refused at 1 a day", function()
		local ok, reason = AdCaps.check(counts(0, 0, 1), TODAY, "CoinPouch", NOW, 0, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("PlacementCap")
		expect(AdCaps.check(counts(0, 0, 0), TODAY, "CoinPouch", NOW, 0, CFG)):toBe(true)
	end)

	test("check: the daily total of 9 refuses even when the placement has room", function()
		expect(AdCaps.check(counts(4, 3, 1), TODAY, "FinishNow", NOW, 0, CFG2)):toBe(true)
		local ok, reason = AdCaps.check(counts(5, 3, 1), TODAY, "FinishNow", NOW, 0, CFG2)
		expect(ok):toBe(false)
		expect(reason):toBe("DailyCap")
	end)

	test("check: the daily total counts only today's ads", function()
		local yesterday: AdCaps.AdCounts = { Date = YESTERDAY, FinishNow = 5, Luck = 3, CoinPouch = 1 }
		expect(AdCaps.check(yesterday, TODAY, "CoinPouch", NOW, 0, CFG)):toBe(true)
	end)

	test("check: the cooldown refuses inside 60 s and allows at 60 s", function()
		local ok, reason = AdCaps.check(FRESH, TODAY, "FinishNow", NOW, NOW - 59, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("Cooldown")
		expect(AdCaps.check(FRESH, TODAY, "FinishNow", NOW, NOW - 60, CFG)):toBe(true)
		expect(AdCaps.check(FRESH, TODAY, "FinishNow", NOW, NOW - 61, CFG)):toBe(true)
	end)

	test("check: a lastAdAt of 0 means no ad has ever been watched", function()
		expect(AdCaps.check(FRESH, TODAY, "FinishNow", NOW, 0, CFG)):toBe(true)
		expect(AdCaps.check(FRESH, TODAY, "Luck", NOW, -5, CFG)):toBe(true)
	end)

	test("check: an unknown placement is refused before anything else", function()
		local ok, reason = AdCaps.check(FRESH, TODAY, "MaxGrow", NOW, NOW - 1, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("Placement")
	end)

	test("check: a placement at its cap reports the cap even while in cooldown", function()
		local ok, reason = AdCaps.check(counts(5, 0, 0), TODAY, "FinishNow", NOW, NOW - 1, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("PlacementCap")
	end)

	test("cooldownLeft: 0 when never watched, counts down otherwise", function()
		expect(AdCaps.cooldownLeft(NOW, 0, CFG)):toBe(0)
		expect(AdCaps.cooldownLeft(NOW, -10, CFG)):toBe(0)
		expect(AdCaps.cooldownLeft(NOW, NOW - 59, CFG)):toBe(1)
		expect(AdCaps.cooldownLeft(NOW, NOW - 60, CFG)):toBe(0)
		expect(AdCaps.cooldownLeft(NOW, NOW - 3600, CFG)):toBe(0)
		expect(AdCaps.cooldownLeft(NOW, NOW, CFG)):toBe(60)
	end)

	test("recordRequest: adds one to the matching placement", function()
		expect(AdCaps.recordRequest(FRESH, TODAY, "FinishNow")):toEqual(counts(1, 0, 0))
		expect(AdCaps.recordRequest(counts(2, 1, 0), TODAY, "Luck")):toEqual(counts(2, 2, 0))
		expect(AdCaps.recordRequest(counts(0, 0, 0), TODAY, "CoinPouch")):toEqual(counts(0, 0, 1))
	end)

	test("recordRequest: a new date resets the other counts first", function()
		local yesterday: AdCaps.AdCounts = { Date = YESTERDAY, FinishNow = 5, Luck = 3, CoinPouch = 1 }
		expect(AdCaps.recordRequest(yesterday, TODAY, "Luck")):toEqual(counts(0, 1, 0))
	end)

	test("recordRequest: never mutates the input counts", function()
		local stored = counts(2, 1, 0)
		local updated = AdCaps.recordRequest(stored, TODAY, "FinishNow")
		expect(updated):toEqual(counts(3, 1, 0))
		expect(stored):toEqual(counts(2, 1, 0))
		expect(stored.FinishNow):toBe(2)
	end)

	test("recordRequest: an unknown placement changes nothing", function()
		local stored = counts(2, 1, 0)
		expect(AdCaps.recordRequest(stored, TODAY, "MaxGrow")):toEqual(stored)
		expect(stored):toEqual(counts(2, 1, 0))
	end)

	test("recordRequest: counts climb until check refuses them", function()
		local stored = AdCaps.recordRequest(FRESH, TODAY, "Luck")
		stored = AdCaps.recordRequest(stored, TODAY, "Luck")
		expect(AdCaps.check(stored, TODAY, "Luck", NOW, 0, CFG)):toBe(true)
		stored = AdCaps.recordRequest(stored, TODAY, "Luck")
		local ok, reason = AdCaps.check(stored, TODAY, "Luck", NOW, 0, CFG)
		expect(ok):toBe(false)
		expect(reason):toBe("PlacementCap")
	end)

	test("AdCaps module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/AdCaps.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
