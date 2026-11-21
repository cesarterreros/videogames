-- Surge.spec.luau - unit tests for the pure surge-window helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Surge = require("../src/shared/Logic/Surge")

-- A UTC midnight 20 000 days after the epoch, so hour arithmetic stays readable.
local DAY = 86400 * 20000
local NOON = DAY + 12 * 3600

return function(test)
	test("isActive: true from the top of the hour until the window closes", function()
		expect(Surge.isActive(NOON, 5)):toBe(true)
		expect(Surge.isActive(NOON + 3 * 60, 5)):toBe(true)
		expect(Surge.isActive(NOON + 4 * 60 + 59, 5)):toBe(true)
	end)

	test("isActive: false from the exact closing second to the end of the hour", function()
		expect(Surge.isActive(NOON + 5 * 60, 5)):toBe(false)
		expect(Surge.isActive(NOON + 30 * 60, 5)):toBe(false)
		expect(Surge.isActive(NOON + 59 * 60 + 59, 5)):toBe(false)
	end)

	test("nextStart: stays on the current second while live, else the next hour boundary", function()
		expect(Surge.nextStart(NOON + 30 * 60, 5)):toBe(NOON + 3600)
		expect(Surge.nextStart(NOON + 2 * 60, 5)):toBe(NOON + 2 * 60)
		expect(Surge.nextStart(NOON + 59 * 60 + 59, 5)):toBe(NOON + 3600)
	end)

	test("Surge module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Surge.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
