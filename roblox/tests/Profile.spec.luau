local expect = require("./lib/expect")
local ProfileTemplate = require("../src/shared/Logic/ProfileTemplate")
local Migration = require("../src/shared/Logic/Migration")
local Seeds = require("../src/shared/Config/Seeds")
local Economy = require("../src/shared/Config/Economy")
local Game = require("../src/shared/Config/Game")

local function sanitizeConfig()
	local ids = {}
	for _, seed in Seeds do
		ids[seed.Id] = true
	end
	return {
		seedIds = ids,
		maxPedestals = Game.MaxPedestals,
		maxLamp = #Economy.LampCosts,
		maxTier = #Seeds,
		startPedestals = Economy.StartPedestals,
		maxCoinPedestals = Economy.MaxCoinPedestals,
	}
end

local function crystal()
	return {
		SeedId = "Quartz",
		PlantedAt = 100,
		ReadyAt = 120,
		SizeRoll = 1.2,
		Mutation = "None",
		InstantGrown = false,
		Shape = 7,
	}
end

return function(test)
	test("ProfileTemplate: version 1 with the starting values", function()
		local p = ProfileTemplate.new()
		expect(p.Version):toBe(1)
		expect(ProfileTemplate.VERSION):toBe(1)
		expect(p.Coins):toBe(0)
		expect(p.SeedBag):toEqual({ Quartz = 1 })
		expect(p.UnlockedPedestals):toBe(Economy.StartPedestals)
		expect(p.Monetization.InstantGrowTokens):toEqual({ S = 0, M = 0, L = 0 })
	end)

	test("ProfileTemplate: new() returns independent copies", function()
		local a = ProfileTemplate.new()
		local b = ProfileTemplate.new()
		a.SeedBag.Quartz = 99
		a.Monetization.AdCounts.Luck = 3
		expect(b.SeedBag.Quartz):toBe(1)
		expect(b.Monetization.AdCounts.Luck):toBe(0)
	end)

	test("Migration: migrate({}) gives a complete v1 profile", function()
		local data = Migration.migrate({}, ProfileTemplate.new())
		expect(data):toEqual(ProfileTemplate.new())
	end)

	test("Migration: migrate keeps existing values and fills missing nested fields", function()
		local data = Migration.migrate({ Coins = 500, Monetization = { LastAdAt = 7 } }, ProfileTemplate.new())
		expect(data.Version):toBe(1)
		expect(data.Coins):toBe(500)
		expect(data.Monetization.LastAdAt):toBe(7)
		expect(data.Monetization.AdCounts.CoinPouch):toBe(0)
	end)

	test("Migration: v1 profile is unchanged", function()
		local p = ProfileTemplate.new()
		p.Coins = 42
		local before = ProfileTemplate.deepCopy(p)
		expect(Migration.migrate(p, ProfileTemplate.new())):toEqual(before)
	end)

	test("Migration: sanitize leaves a valid profile alone", function()
		local p = ProfileTemplate.new()
		p.Pedestals["1"] = crystal()
		p.Pedestals["13"] = crystal()
		local before = ProfileTemplate.deepCopy(p)
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(#issues):toBe(0)
		expect(data):toEqual(before)
	end)

	test("Migration: sanitize fixes impossible values and reports each", function()
		local p = ProfileTemplate.new()
		p.Coins = -50
		p.SeedBag.Diamond = 3
		p.Pedestals["14"] = crystal()
		p.Pedestals["2"] = crystal()
		p.LampLevel = 9
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(data.Coins):toBe(0)
		expect(data.SeedBag.Diamond):toBeNil()
		expect(data.SeedBag.Quartz):toBe(1)
		expect(data.Pedestals["14"]):toBeNil()
		expect(data.Pedestals["2"]).never:toBeNil()
		expect(data.LampLevel):toBe(5)
		expect(#issues):toBe(4)
	end)

	test("Migration: sanitize rejects malformed crystals and keys", function()
		local p = ProfileTemplate.new()
		local bad = crystal()
		bad.Mutation = "Rainbow"
		p.Pedestals["3"] = bad
		p.Pedestals["03"] = crystal()
		p.Pedestals["1.5"] = crystal()
		p.Coins = 0 / 0
		p.UnlockedPedestals = 50
		local data = Migration.sanitize(p, sanitizeConfig())
		expect(next(data.Pedestals)):toBeNil()
		expect(data.Coins):toBe(0)
		expect(data.UnlockedPedestals):toBe(10)
	end)

	test("Migration: sanitize flags a profile from a newer version", function()
		local p = ProfileTemplate.new()
		p.Version = 2
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(data.Version):toBe(2)
		expect(#issues):toBe(1)
	end)

	test("ProfileTemplate: Settings.Brightness defaults to Normal", function()
		expect(ProfileTemplate.new().Settings.Brightness):toBe("Normal")
	end)

	test("Migration: an old profile without Brightness gets Normal and keeps its other settings", function()
		-- Pre-version data goes through migrate's fill step.
		local data = Migration.migrate({ Settings = { AutoShatter = true, Music = false } }, ProfileTemplate.new())
		expect(data.Settings.Brightness):toBe("Normal")
		expect(data.Settings.AutoShatter):toBe(true)
		expect(data.Settings.Music):toBe(false)

		-- A v1 profile saved before the field existed: in the game Reconcile fills it first;
		-- sanitize is the safety net and still ends with Normal.
		local p = ProfileTemplate.new()
		p.Settings.Brightness = nil
		local fixed = Migration.sanitize(p, sanitizeConfig())
		expect(fixed.Settings.Brightness):toBe("Normal")
		expect(fixed.Settings.Music):toBe(true)
	end)

	test("Migration: sanitize repairs an unknown Brightness and reports it", function()
		local p = ProfileTemplate.new()
		p.Settings.Brightness = "Purple"
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(data.Settings.Brightness):toBe("Normal")
		expect(#issues):toBe(1)
		expect(issues[1]):toBe("brightness Purple")

		local q = ProfileTemplate.new()
		q.Settings.Brightness = 3
		local data2, issues2 = Migration.sanitize(q, sanitizeConfig())
		expect(data2.Settings.Brightness):toBe("Normal")
		expect(#issues2):toBe(1)
	end)

	test("Migration: sanitize keeps a valid Brightness", function()
		local p = ProfileTemplate.new()
		p.Settings.Brightness = "Dark"
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(data.Settings.Brightness):toBe("Dark")
		expect(#issues):toBe(0)
	end)

	test("Migration: sanitize replaces a Settings value that isn't a table", function()
		local p = ProfileTemplate.new()
		p.Settings = "broken"
		local data, issues = Migration.sanitize(p, sanitizeConfig())
		expect(data.Settings.Brightness):toBe("Normal")
		expect(#issues):toBe(2)
	end)

	test("Migration: Brightness names match Config/Lighting", function()
		local Lighting = require("../src/shared/Config/Lighting")
		expect(ProfileTemplate.new().Settings.Brightness):toBe(Lighting.Default)
		local count = 0
		for name in Lighting.Presets do
			count += 1
			local p = ProfileTemplate.new()
			p.Settings.Brightness = name
			local data, issues = Migration.sanitize(p, sanitizeConfig())
			expect(data.Settings.Brightness):toBe(name)
			expect(#issues):toBe(0)
		end
		expect(count):toBe(3)
	end)

	test("Logic modules contain no require", function()
		local fs = require("@lune/fs")
		for _, name in { "ProfileTemplate", "Migration", "RateLimiter", "Validate", "WeekId", "Format" } do
			local source = fs.readFile("src/shared/Logic/" .. name .. ".luau")
			-- Look for an actual call (require( / require" / require'), not the word in a comment.
			expect(string.find(source, "require%s*[%(\"']")):toBeNil()
		end
	end)
end
