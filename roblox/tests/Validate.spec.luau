local expect = require("./lib/expect")
local Validate = require("../src/shared/Logic/Validate")

local function check(schema, ...)
	return Validate.check(schema, { ... }, select("#", ...))
end

local PLANT = { { kind = "int", min = 1, max = 13 }, { kind = "enum", values = { "Quartz", "Amethyst" } } }

return function(test)
	test("Validate: accepts a valid call", function()
		expect((check(PLANT, 4, "Quartz"))):toBe(true)
	end)

	test("Validate: rejects wrong types", function()
		expect((check(PLANT, "4", "Quartz"))):toBe(false)
		expect((check(PLANT, 4, 7))):toBe(false)
		expect((check(PLANT, 4, {}))):toBe(false)
		expect((check({ { kind = "bool" } }, 1))):toBe(false)
		expect((check({ { kind = "string", maxLen = 3 } }, 5))):toBe(false)
	end)

	test("Validate: rejects a float for an int", function()
		local ok, reason = check(PLANT, 4.5, "Quartz")
		expect(ok):toBe(false)
		expect(reason):toBe("arg 1: expected integer")
	end)

	test("Validate: rejects out-of-range values", function()
		expect((check(PLANT, 0, "Quartz"))):toBe(false)
		expect((check(PLANT, 14, "Quartz"))):toBe(false)
		expect((check(PLANT, -1, "Quartz"))):toBe(false)
	end)

	test("Validate: rejects NaN and infinity", function()
		expect((check(PLANT, 0 / 0, "Quartz"))):toBe(false)
		expect((check(PLANT, math.huge, "Quartz"))):toBe(false)
		expect((check({ { kind = "number" } }, -math.huge))):toBe(false)
	end)

	test("Validate: rejects extra and missing arguments", function()
		expect((check(PLANT, 4, "Quartz", "extra"))):toBe(false)
		expect((check(PLANT, 4))):toBe(false)
		-- A trailing nil still counts as an extra argument.
		expect((check({}, nil))):toBe(false)
		expect((check({}))):toBe(true)
	end)

	test("Validate: rejects unknown enum values, accepts mixed enums", function()
		expect((check(PLANT, 4, "Diamond"))):toBe(false)
		local goal = { { kind = "enum", values = { 1, 2, 3, "Bonus" } } }
		expect((check(goal, 2))):toBe(true)
		expect((check(goal, "Bonus"))):toBe(true)
		expect((check(goal, 4))):toBe(false)
		expect((check(goal, "2"))):toBe(false)
	end)

	test("Validate: rejects over-long strings", function()
		local schema = { { kind = "string", maxLen = 3 } }
		expect((check(schema, "abc"))):toBe(true)
		expect((check(schema, "abcd"))):toBe(false)
	end)

	test("Validate: optional arguments may be missing", function()
		local ad = {
			{ kind = "enum", values = { "FinishNow", "Luck" } },
			{ kind = "int", min = 1, max = 13, optional = true },
		}
		expect((check(ad, "Luck"))):toBe(true)
		expect((check(ad, "FinishNow", 3))):toBe(true)
		expect((check(ad, "FinishNow", 99))):toBe(false)
	end)
end
