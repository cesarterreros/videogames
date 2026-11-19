-- Growth.spec.luau - unit tests for the pure growth math helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Growth = require("../src/shared/Logic/Growth")

-- A plant started at t=1000 with a 600 s window is ready at t=1600.
local PLANTED = 1000
local READY = 1600

return function(test)
	test("growSeconds: lamp levels trim the timer by lampStep each", function()
		expect(Growth.growSeconds(100, 0, 0.05)):toBeNear(100)
		expect(Growth.growSeconds(100, 5, 0.05)):toBeNear(75)
		expect(Growth.growSeconds(100, 10, 0.05)):toBeNear(50)
	end)

	test("growSeconds: speedMult scales the timer", function()
		expect(Growth.growSeconds(100, 0, 0.05, 0.5)):toBe(50)
		expect(Growth.growSeconds(100, 5, 0.05, 2)):toBeNear(150)
	end)

	test("growSeconds: never below one second", function()
		expect(Growth.growSeconds(0.5, 0, 0.05)):toBe(1)
		expect(Growth.growSeconds(10, 5, 0.05, 0.01)):toBe(1)
	end)

	test("growSeconds: result is not rounded to a whole second", function()
		expect(Growth.growSeconds(20, 1, 0.05)):toBeNear(19)
		-- 21 s minus one lamp step is 19.95 s, kept as a fraction rather than rounded to 20.
		expect(Growth.growSeconds(21, 1, 0.05)):toBeNear(19.95)
		expect(Growth.growSeconds(21, 1, 0.05)).never:toBe(20)
	end)

	test("progress: 0 at planting, half way midway, 1 at ready", function()
		expect(Growth.progress(PLANTED, PLANTED, READY)):toBeNear(0)
		expect(Growth.progress(PLANTED + 300, PLANTED, READY)):toBeNear(0.5)
		expect(Growth.progress(PLANTED + 150, PLANTED, READY)):toBeNear(0.25)
		expect(Growth.progress(READY, PLANTED, READY)):toBeNear(1)
	end)

	test("progress: clamped to 0..1 for times outside the window", function()
		expect(Growth.progress(PLANTED - 500, PLANTED, READY)):toBeNear(0)
		expect(Growth.progress(READY + 500, PLANTED, READY)):toBeNear(1)
	end)

	test("progress: an inverted window counts as complete", function()
		expect(Growth.progress(PLANTED, PLANTED, PLANTED)):toBeNear(1)
		expect(Growth.progress(PLANTED, PLANTED, PLANTED - 100)):toBeNear(1)
	end)

	test("isReady: false one second before ready, true at and after ready", function()
		expect(Growth.isReady(READY - 1, READY)):toBe(false)
		expect(Growth.isReady(READY, READY)):toBe(true)
		expect(Growth.isReady(READY + 3600, READY)):toBe(true)
	end)

	test("overgrowth: 0 before and at ready", function()
		expect(Growth.overgrowth(READY - 1800, READY, 0.10, 0.50)):toBeNear(0)
		expect(Growth.overgrowth(READY, READY, 0.10, 0.50)):toBeNear(0)
	end)

	test("overgrowth: climbs continuously per hour", function()
		expect(Growth.overgrowth(READY + 3600, READY, 0.10, 0.50)):toBeNear(0.10)
		expect(Growth.overgrowth(READY + 1800, READY, 0.10, 0.50)):toBeNear(0.05)
		expect(Growth.overgrowth(READY + 900, READY, 0.10, 0.50)):toBeNear(0.025)
	end)

	test("overgrowth: hits the cap and stays there", function()
		expect(Growth.overgrowth(READY + 5 * 3600, READY, 0.10, 0.50)):toBeNear(0.50)
		expect(Growth.overgrowth(READY + 10 * 3600, READY, 0.10, 0.50)):toBeNear(0.50)
	end)

	test("shatterValue: plain normal roll", function()
		local coins, carats = Growth.shatterValue(15, 1.0, 1.2, 1, 0)
		expect(coins):toBe(18)
		expect(carats):toBeNear(1.2)
	end)

	test("shatterValue: big mutated roll pays coins and carats", function()
		local coins, carats = Growth.shatterValue(60, 1.5, 2.0, 5, 0.10)
		expect(coins):toBe(660)
		expect(carats):toBeNear(3.3)
	end)

	test("shatterValue: coin multiplier doubles the coins only", function()
		local coins, carats = Growth.shatterValue(15, 1, 1.0, 1, 0, 2)
		expect(coins):toBe(30)
		expect(carats):toBeNear(1.0)
	end)

	test("shatterValue: overgrowth lifts coins and carats", function()
		local coins, carats = Growth.shatterValue(15, 1, 1.0, 2, 0.5)
		expect(coins):toBe(45)
		expect(carats):toBeNear(1.5)
	end)

	test("shatterValue: float products do not floor down a coin", function()
		-- 100 * 0.29 is 28.999999999999996 in doubles; the payout must still be 29 coins.
		local coins, carats = Growth.shatterValue(100, 1, 0.29, 1, 0)
		expect(coins):toBe(29)
		expect(carats):toBeNear(0.29)
	end)

	test("Growth module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Growth.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
