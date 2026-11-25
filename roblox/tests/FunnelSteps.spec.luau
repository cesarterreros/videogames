-- FunnelSteps.spec.luau - unit tests for the in-order funnel step helper (change E, finding T5).

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local FunnelSteps = require("../src/shared/Logic/FunnelSteps")

return function(test)
	test("toLog: the next step in order is logged alone", function()
		local steps = FunnelSteps.toLog({ [1] = true }, 2)
		expect(#steps):toBe(1)
		expect(steps[1]):toBe(2)
	end)

	test("toLog: step 3 before step 2 logs 2 first, then 3 (T5)", function()
		local steps = FunnelSteps.toLog({ [1] = true }, 3)
		expect(#steps):toBe(2)
		expect(steps[1]):toBe(2)
		expect(steps[2]):toBe(3)
	end)

	test("toLog: step 2 after step 3 logs nothing (each step once)", function()
		local logged = { [1] = true }
		FunnelSteps.mark(logged, FunnelSteps.toLog(logged, 3))
		expect(#FunnelSteps.toLog(logged, 2)):toBe(0)
		expect(#FunnelSteps.toLog(logged, 3)):toBe(0)
	end)

	test("toLog: from nothing logged, step 1 is logged alone", function()
		local steps = FunnelSteps.toLog({}, 1)
		expect(#steps):toBe(1)
		expect(steps[1]):toBe(1)
	end)

	test("toLog: invalid steps log nothing", function()
		expect(#FunnelSteps.toLog({}, 0)):toBe(0)
		expect(#FunnelSteps.toLog({}, -1)):toBe(0)
		expect(#FunnelSteps.toLog({}, 2.5)):toBe(0)
		expect(#FunnelSteps.toLog({}, 0 / 0)):toBe(0)
	end)

	test("mark: marks exactly the given steps", function()
		local logged = {}
		FunnelSteps.mark(logged, { 1, 3 })
		expect(logged[1]):toBe(true)
		expect(logged[2]):toBeNil()
		expect(logged[3]):toBe(true)
	end)

	test("FunnelSteps module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/FunnelSteps.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
