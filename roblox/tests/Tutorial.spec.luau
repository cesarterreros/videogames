-- Tutorial.spec.luau - unit tests for the pure tutorial step rules (batch 4, task 11).

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Tutorial = require("../src/shared/Logic/Tutorial")
local Progression = require("../src/shared/Config/Progression")

local GROW = Progression.Tutorial.GrowSeconds
local BONUS = Progression.Tutorial.BonusCoins
local GLOWING_AT = Progression.Tutorial.GuaranteedGlowingOnShatter

local function at(step: number, done: boolean?)
	return { Step = step, Done = done == true }
end

return function(test)
	test("config: 8 s grow, 50 bonus coins, Glowing on the 3rd crystal", function()
		expect(GROW):toBe(8)
		expect(BONUS):toBe(50)
		expect(GLOWING_AT):toBe(3)
		expect(#Tutorial.StepNames):toBe(8)
	end)

	test("the full new-player run reaches steps 1..8 in order, each once", function()
		local t = at(0)
		local logged = {}
		local function apply(event, info)
			local step, reached, done = Tutorial.advance(t, event, info)
			for _, s in reached do
				table.insert(logged, s)
			end
			t = { Step = step, Done = done }
		end
		apply("Load")
		apply("Load") -- a second load changes nothing
		apply("Plant", { plantsAfter = 1 })
		apply("Shatter", { mutation = "None" })
		apply("Action", { step = 4 })
		apply("BuySeed")
		apply("BuySeed") -- buying again changes nothing
		apply("Plant", { plantsAfter = 2 })
		apply("Plant", { plantsAfter = 3 })
		apply("Shatter", { mutation = "None" }) -- plant 2, no mutation: still step 6
		apply("Shatter", { mutation = "Glowing" })
		apply("Action", { step = 8 })
		expect(table.concat(logged, ",")):toBe("1,2,3,4,5,6,7,8")
		expect(t.Done):toBe(true)
		expect(Tutorial.isActive(t)):toBe(false)
	end)

	test("TutorialAction: only 4 or 8, and only as the next step", function()
		local refused = {
			{ at(3), 5 },
			{ at(3), 8 },
			{ at(2), 4 },
			{ at(4), 4 },
			{ at(6), 8 },
			{ at(7), 7 },
			{ at(1), 2 },
			{ at(0), 1 },
		}
		for _, case in refused do
			local step, reached = Tutorial.advance(case[1], "Action", { step = case[2] })
			expect(step):toBe(case[1].Step)
			expect(#reached):toBe(0)
		end
		local step, reached = Tutorial.advance(at(3), "Action", { step = 4 })
		expect(step):toBe(4)
		expect(reached[1]):toBe(4)
		local step8, _, done = Tutorial.advance(at(7), "Action", { step = 8 })
		expect(step8):toBe(8)
		expect(done):toBe(true)
		local _, none = Tutorial.advance(at(3), "Action", { step = "4" })
		expect(#none):toBe(0)
	end)

	test("a purchase that arrives before TutorialAction(4) logs 4, then 5", function()
		local step, reached = Tutorial.advance(at(3), "BuySeed")
		expect(step):toBe(5)
		expect(table.concat(reached, ",")):toBe("4,5")
	end)

	test("step 6 needs 3 plants in total; step 7 needs a mutated crystal at step 6", function()
		expect((Tutorial.advance(at(5), "Plant", { plantsAfter = 2 }))):toBe(5)
		expect((Tutorial.advance(at(5), "Plant", { plantsAfter = 3 }))):toBe(6)
		expect((Tutorial.advance(at(5), "Shatter", { mutation = "Glowing" }))):toBe(5)
		expect((Tutorial.advance(at(6), "Shatter", { mutation = "None" }))):toBe(6)
		expect((Tutorial.advance(at(6), "Shatter", { mutation = "Molten" }))):toBe(7)
	end)

	test("finished tutorial: no events change anything", function()
		for _, event in { "Load", "Plant", "Shatter", "BuySeed", "Action" } do
			local step, reached, done =
				Tutorial.advance(at(8, true), event, { plantsAfter = 9, mutation = "Glowing", step = 8 })
			expect(step):toBe(8)
			expect(#reached):toBe(0)
			expect(done):toBe(true)
		end
	end)

	test("8-second grow only for the very first crystal of an active tutorial", function()
		expect(Tutorial.growOverride(at(1), 0, GROW)):toBe(8)
		expect(Tutorial.growOverride(at(0), 0, GROW)):toBe(8)
		expect(Tutorial.growOverride(at(1), 1, GROW)):toBeNil()
		expect(Tutorial.growOverride(at(5), 0, GROW)):toBeNil()
		expect(Tutorial.growOverride(at(1, true), 0, GROW)):toBeNil()
	end)

	test("forced Glowing only for the 3rd plant overall of an active tutorial", function()
		expect(Tutorial.forcedMutation(at(5), 2, GLOWING_AT)):toBe("Glowing")
		expect(Tutorial.forcedMutation(at(5), 1, GLOWING_AT)):toBeNil()
		expect(Tutorial.forcedMutation(at(6), 3, GLOWING_AT)):toBeNil()
		expect(Tutorial.forcedMutation(at(8, true), 2, GLOWING_AT)):toBeNil()
	end)

	test("bonus coins only on the shatter at step 2", function()
		expect(Tutorial.bonusCoins(at(2), BONUS)):toBe(50)
		expect(Tutorial.bonusCoins(at(3), BONUS)):toBe(0)
		expect(Tutorial.bonusCoins(at(1), BONUS)):toBe(0)
		expect(Tutorial.bonusCoins(at(2, true), BONUS)):toBe(0)
	end)

	test("existing profiles skip: step 0 with shatters; plants = shatters + occupied pedestals", function()
		expect(Tutorial.shouldSkip(at(0), 10)):toBe(true)
		expect(Tutorial.shouldSkip(at(0), 0)):toBe(false)
		expect(Tutorial.shouldSkip(at(3), 1)):toBe(false) -- mid-tutorial players keep their step
		expect(Tutorial.shouldSkip(at(8, true), 5)):toBe(false)
		expect(Tutorial.plantsSoFar(1, 2)):toBe(3)
	end)

	test("advance does not modify its input", function()
		local t = at(2)
		Tutorial.advance(t, "Shatter", { mutation = "None" })
		expect(t.Step):toBe(2)
		expect(t.Done):toBe(false)
	end)

	test("Tutorial module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Tutorial.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
