-- Admin.spec.luau - unit tests for the dev-only "/cg" command parser and permission rule (batch 6, task 5).

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local AdminCommands = require("../src/shared/Logic/AdminCommands")

local SEEDS = { "Quartz", "Amethyst", "Citrine", "Voidheart" }

-- Parses and returns only the command (nil when refused).
local function cmd(text: any)
	local command = AdminCommands.parse(text, SEEDS)
	return command
end

local DEV = 10777641396
local LIVE = 99999

return function(test)
	test("coins: whole numbers from 0 to MaxCoins", function()
		local c = cmd("/cg coins 500")
		expect(c.Name):toBe("coins")
		expect(c.Amount):toBe(500)
		expect(cmd("/cg coins 0").Amount):toBe(0)
		expect(cmd("/cg coins 1000000000").Amount):toBe(AdminCommands.MaxCoins)
	end)

	test("coins: refuses negatives, fractions, words, NaN, huge and missing values", function()
		expect(cmd("/cg coins -5")):toBeNil()
		expect(cmd("/cg coins 1.5")):toBeNil()
		expect(cmd("/cg coins lots")):toBeNil()
		expect(cmd("/cg coins nan")):toBeNil()
		expect(cmd("/cg coins inf")):toBeNil()
		expect(cmd("/cg coins 1e9")):toBeNil()
		expect(cmd("/cg coins 1000000001")):toBeNil()
		expect(cmd("/cg coins 99999999999999999999")):toBeNil()
		expect(cmd("/cg coins")):toBeNil()
		expect(cmd("/cg coins 5 6")):toBeNil()
	end)

	test("refusals carry a reason for the player", function()
		local command, reason = AdminCommands.parse("/cg coins -5", SEEDS)
		expect(command):toBeNil()
		expect(type(reason)):toBe("string")
	end)

	test("seeds: known seed (any case) and 1..MaxSeeds", function()
		local c = cmd("/cg seeds citrine 3")
		expect(c.Name):toBe("seeds")
		expect(c.SeedId):toBe("Citrine")
		expect(c.Amount):toBe(3)
		expect(cmd("/cg seeds Voidheart 999").Amount):toBe(999)
		expect(cmd("/cg seeds Ruby 3")):toBeNil()
		expect(cmd("/cg seeds Quartz 0")):toBeNil()
		expect(cmd("/cg seeds Quartz 1000")):toBeNil()
		expect(cmd("/cg seeds Quartz")):toBeNil()
		expect(cmd("/cg seeds 3 Quartz")):toBeNil()
	end)

	test("ready, wipe, tutorial reset and daily reset take no other words", function()
		expect(cmd("/cg ready").Name):toBe("ready")
		expect(cmd("/cg wipe").Name):toBe("wipe")
		expect(cmd("/cg tutorial reset").Name):toBe("tutorialReset")
		expect(cmd("/cg daily reset").Name):toBe("dailyReset")
		expect(cmd("/cg ready now")):toBeNil()
		expect(cmd("/cg wipe all")):toBeNil()
		expect(cmd("/cg tutorial")):toBeNil()
		expect(cmd("/cg daily claim")):toBeNil()
	end)

	test("tier: 1..MaxTier", function()
		expect(cmd("/cg tier 1").Amount):toBe(1)
		expect(cmd("/cg tier 10").Amount):toBe(10)
		expect(cmd("/cg tier 0")):toBeNil()
		expect(cmd("/cg tier 11")):toBeNil()
	end)

	test("case and spacing don't matter; other aliases and junk are refused", function()
		expect(cmd("  /CG   Coins   7 ").Amount):toBe(7)
		expect(cmd("/cg")):toBeNil()
		expect(cmd("/cgx coins 5")):toBeNil()
		expect(cmd("cg coins 5")):toBeNil()
		expect(cmd("")):toBeNil()
		expect(cmd(nil)):toBeNil()
		expect(cmd(42)):toBeNil()
		expect(cmd("/cg fly")):toBeNil()
	end)

	test("isAllowed: anyone in Studio", function()
		expect(AdminCommands.isAllowed(true, 0, DEV, false, 0, -1)):toBe(true)
	end)

	test("isAllowed: in DEV only the owning user", function()
		expect(AdminCommands.isAllowed(false, DEV, DEV, true, 123, 123)):toBe(true)
		expect(AdminCommands.isAllowed(false, DEV, DEV, true, 123, 456)):toBe(false)
		expect(AdminCommands.isAllowed(false, DEV, DEV, false, 123, 123)):toBe(false)
	end)

	test("isAllowed: never in the live experience, even for the owner", function()
		expect(AdminCommands.isAllowed(false, LIVE, DEV, true, 123, 123)):toBe(false)
		expect(AdminCommands.isAllowed(false, 0, 0, true, 123, 123)):toBe(false)
	end)

	test("existsHere: Studio or the DEV universe only", function()
		expect(AdminCommands.existsHere(true, LIVE, DEV)):toBe(true)
		expect(AdminCommands.existsHere(false, DEV, DEV)):toBe(true)
		expect(AdminCommands.existsHere(false, LIVE, DEV)):toBe(false)
		expect(AdminCommands.existsHere(false, 0, 0)):toBe(false)
	end)

	test("AdminCommands module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/AdminCommands.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
