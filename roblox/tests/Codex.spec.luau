-- Codex.spec.luau - unit tests for the pure Crystal Codex helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Codex = require("../src/shared/Logic/Codex")

return function(test)
	test("record: true the first time, false after", function()
		local c = {}
		expect(Codex.record(c, "Quartz", "None")):toBe(true)
		expect(Codex.record(c, "Quartz", "None")):toBe(false)
		expect(c.Quartz.None):toBe(true)
	end)

	test("record: each mutation and each seed is its own variant", function()
		local c = {}
		expect(Codex.record(c, "Quartz", "None")):toBe(true)
		expect(Codex.record(c, "Quartz", "Glowing")):toBe(true)
		expect(Codex.record(c, "Amethyst", "None")):toBe(true)
		expect(Codex.record(c, "Quartz", "Glowing")):toBe(false)
	end)

	test("isComplete: needs all 4 variants", function()
		local c = {}
		expect(Codex.isComplete(c, "Quartz")):toBe(false)
		Codex.record(c, "Quartz", "None")
		Codex.record(c, "Quartz", "Glowing")
		Codex.record(c, "Quartz", "Molten")
		expect(Codex.isComplete(c, "Quartz")):toBe(false)
		Codex.record(c, "Quartz", "Prismatic")
		expect(Codex.isComplete(c, "Quartz")):toBe(true)
		expect(Codex.isComplete(c, "Amethyst")):toBe(false)
	end)

	test("isComplete: a stored false does not count", function()
		local c = { Quartz = { None = true, Glowing = true, Molten = true, Prismatic = false } }
		expect(Codex.isComplete(c, "Quartz")):toBe(false)
	end)

	test("Variants lists the 4 names in order", function()
		expect(#Codex.Variants):toBe(4)
		expect(Codex.Variants[1]):toBe("None")
		expect(Codex.Variants[2]):toBe("Glowing")
		expect(Codex.Variants[3]):toBe("Molten")
		expect(Codex.Variants[4]):toBe("Prismatic")
	end)

	test("Codex module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Codex.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
