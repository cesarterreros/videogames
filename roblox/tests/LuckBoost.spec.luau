-- LuckBoost.spec.luau - unit tests for the pure luck-boost helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local LuckBoost = require("../src/shared/Logic/LuckBoost")

-- A fixed UTC second, so every offset below stays readable.
local NOW = 1800000000

-- The shipping Monetization/LuckBoost tuning: 15 minutes per purchase, 60 minutes of bank,
-- a x2 luck multiplier, a x2 surge multiplier and a x3 ceiling on the combined multiplier.
local MINUTES = 15
local MAX_BANK = 60
local LUCK = 2
local SURGE = 2
local MAX_TOTAL = 3

-- The free-luck ad needs the boost to be nearly gone: at most 5 minutes still on the clock.
local AD_MAX_LEFT = 300

return function(test)
	test("extend: no boost yet gives a plain 15 minutes from now", function()
		expect(LuckBoost.extend(0, NOW, MINUTES, MAX_BANK)):toBe(NOW + 900)
	end)

	test("extend: an expired boost also starts a plain 15 minutes from now", function()
		expect(LuckBoost.extend(NOW - 100, NOW, MINUTES, MAX_BANK)):toBe(NOW + 900)
		expect(LuckBoost.extend(NOW - 3600, NOW, MINUTES, MAX_BANK)):toBe(NOW + 900)
	end)

	test("extend: buying while active adds to the end of the current boost", function()
		expect(LuckBoost.extend(NOW + 300, NOW, MINUTES, MAX_BANK)):toBe(NOW + 1200)
		expect(LuckBoost.extend(NOW + 900, NOW, MINUTES, MAX_BANK)):toBe(NOW + 1800)
	end)

	test("extend: four purchases in a row fill the 60 minute bank exactly", function()
		local endsAt = LuckBoost.extend(0, NOW, MINUTES, MAX_BANK)
		expect(endsAt):toBe(NOW + 900)
		endsAt = LuckBoost.extend(endsAt, NOW, MINUTES, MAX_BANK)
		expect(endsAt):toBe(NOW + 1800)
		endsAt = LuckBoost.extend(endsAt, NOW, MINUTES, MAX_BANK)
		expect(endsAt):toBe(NOW + 2700)
		endsAt = LuckBoost.extend(endsAt, NOW, MINUTES, MAX_BANK)
		expect(endsAt):toBe(NOW + 3600)
	end)

	test("extend: a fifth purchase cannot push the bank past one hour", function()
		expect(LuckBoost.extend(NOW + 3600, NOW, MINUTES, MAX_BANK)):toBe(NOW + 3600)
		expect(LuckBoost.extend(NOW + 3500, NOW, MINUTES, MAX_BANK)):toBe(NOW + 3600)
	end)

	test("isActive: true before the end, false at and after it", function()
		local endsAt = NOW + 600
		expect(LuckBoost.isActive(NOW, endsAt)):toBe(true)
		expect(LuckBoost.isActive(NOW + 599, endsAt)):toBe(true)
		expect(LuckBoost.isActive(NOW + 600, endsAt)):toBe(false)
		expect(LuckBoost.isActive(NOW + 601, endsAt)):toBe(false)
		expect(LuckBoost.isActive(NOW, 0)):toBe(false)
	end)

	test("secondsLeft: counts down and stops at zero", function()
		local endsAt = NOW + 600
		expect(LuckBoost.secondsLeft(NOW, endsAt)):toBe(600)
		expect(LuckBoost.secondsLeft(NOW + 599, endsAt)):toBe(1)
		expect(LuckBoost.secondsLeft(NOW + 600, endsAt)):toBe(0)
		expect(LuckBoost.secondsLeft(NOW + 601, endsAt)):toBe(0)
		expect(LuckBoost.secondsLeft(NOW, 0)):toBe(0)
	end)

	test("chanceMult: nothing active leaves the mutation chance alone", function()
		expect(LuckBoost.chanceMult(NOW, 0, false, LUCK, SURGE, MAX_TOTAL)):toBe(1)
		expect(LuckBoost.chanceMult(NOW, NOW - 1, false, LUCK, SURGE, MAX_TOTAL)):toBe(1)
	end)

	test("chanceMult: luck alone doubles, surge alone doubles", function()
		expect(LuckBoost.chanceMult(NOW, NOW + 900, false, LUCK, SURGE, MAX_TOTAL)):toBe(2)
		expect(LuckBoost.chanceMult(NOW, 0, true, LUCK, SURGE, MAX_TOTAL)):toBe(2)
	end)

	test("chanceMult: luck and surge together hit the x3 cap, not x4", function()
		expect(LuckBoost.chanceMult(NOW, NOW + 900, true, LUCK, SURGE, MAX_TOTAL)):toBe(3)
	end)

	test("chanceMult: an expired boost plus a surge still gives only the surge", function()
		expect(LuckBoost.chanceMult(NOW, NOW - 1, true, LUCK, SURGE, MAX_TOTAL)):toBe(2)
		expect(LuckBoost.chanceMult(NOW, NOW, true, LUCK, SURGE, MAX_TOTAL)):toBe(2)
	end)

	test("canWatchAd: allowed with no boost at all", function()
		expect(LuckBoost.canWatchAd(NOW, 0, AD_MAX_LEFT)):toBe(true)
		expect(LuckBoost.canWatchAd(NOW, NOW - 500, AD_MAX_LEFT)):toBe(true)
	end)

	test("canWatchAd: allowed at exactly 300 seconds left, refused at 301", function()
		expect(LuckBoost.canWatchAd(NOW, NOW + 300, AD_MAX_LEFT)):toBe(true)
		expect(LuckBoost.canWatchAd(NOW, NOW + 299, AD_MAX_LEFT)):toBe(true)
		expect(LuckBoost.canWatchAd(NOW, NOW + 301, AD_MAX_LEFT)):toBe(false)
		expect(LuckBoost.canWatchAd(NOW, NOW + 900, AD_MAX_LEFT)):toBe(false)
	end)

	test("LuckBoost module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/LuckBoost.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
