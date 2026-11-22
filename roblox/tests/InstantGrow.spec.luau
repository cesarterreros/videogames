-- InstantGrow.spec.luau - unit tests for the pure instant-grow helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local InstantGrow = require("../src/shared/Logic/InstantGrow")

-- The real game config: S covers 15 minutes, M covers 2 hours.
local CFG = { S = 900, M = 7200 }

return function(test)
	test("TIERS: smallest tier first", function()
		expect(InstantGrow.TIERS):toEqual({ "S", "M", "L" })
	end)

	test("tierFor: the S/M boundary", function()
		expect(InstantGrow.tierFor(0, CFG)):toBe("S")
		expect(InstantGrow.tierFor(900, CFG)):toBe("S")
		expect(InstantGrow.tierFor(901, CFG)):toBe("M")
	end)

	test("tierFor: the M/L boundary and long timers", function()
		expect(InstantGrow.tierFor(7200, CFG)):toBe("M")
		expect(InstantGrow.tierFor(7201, CFG)):toBe("L")
		expect(InstantGrow.tierFor(30000, CFG)):toBe("L")
	end)

	test("tierFor: zero and negative seconds are S", function()
		expect(InstantGrow.tierFor(-1, CFG)):toBe("S")
		expect(InstantGrow.tierFor(-3600, CFG)):toBe("S")
	end)

	test("productKey: one key per tier", function()
		expect(InstantGrow.productKey("S")):toBe("InstantGrowS")
		expect(InstantGrow.productKey("M")):toBe("InstantGrowM")
		expect(InstantGrow.productKey("L")):toBe("InstantGrowL")
	end)

	test("pickToken: the exact tier while its tokens remain", function()
		expect(InstantGrow.pickToken({ S = 1, M = 1, L = 1 }, "S")):toBe("S")
		expect(InstantGrow.pickToken({ S = 1, M = 1, L = 1 }, "M")):toBe("M")
		expect(InstantGrow.pickToken({ S = 1, M = 1, L = 1 }, "L")):toBe("L")
	end)

	test("pickToken: a bigger tier when the exact one is empty", function()
		expect(InstantGrow.pickToken({ S = 0, M = 0, L = 2 }, "S")):toBe("L")
		expect(InstantGrow.pickToken({ S = 0, M = 3, L = 2 }, "S")):toBe("M")
		expect(InstantGrow.pickToken({ S = 0, M = 0, L = 4 }, "M")):toBe("L")
	end)

	test("pickToken: nil when only smaller tiers are owned", function()
		expect(InstantGrow.pickToken({ S = 1, M = 0, L = 0 }, "M")):toBeNil()
		expect(InstantGrow.pickToken({ S = 5, M = 5, L = 0 }, "L")):toBeNil()
	end)

	test("pickToken: nil when every tier is empty", function()
		expect(InstantGrow.pickToken({ S = 0, M = 0, L = 0 }, "S")):toBeNil()
		expect(InstantGrow.pickToken({ S = 0, M = 0, L = 0 }, "L")):toBeNil()
	end)

	test("pickToken: missing counts are treated as 0", function()
		local tokens: any = { S = 1 }
		expect(InstantGrow.pickToken(tokens, "S")):toBe("S")
		expect(InstantGrow.pickToken(tokens, "M")):toBeNil()
	end)

	test("pickToken: non-number counts are treated as 0", function()
		local tokens: any = { S = 0, M = 0, L = "many" }
		expect(InstantGrow.pickToken(tokens, "S")):toBeNil()
	end)

	test("InstantGrow module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/InstantGrow.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
