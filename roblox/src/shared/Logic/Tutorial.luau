--!strict
-- Pure tutorial rules: which onboarding step a player reaches on each event, and the three tutorial-only
-- favours (fast first crystal, guaranteed Glowing, bonus coins). The profile's Tutorial table and counts are
-- passed in, so nothing here reads the clock, the profile store or Roblox APIs.
--
-- Plants so far = Stats.Shatters + crystals on pedestals. For a tutorial player that is exact: every crystal
-- they planted is either still on a pedestal or was shattered (existing players skip the tutorial, see shouldSkip).

export type TutorialData = {
	Step: number, -- last step reached, 0..8
	Done: boolean,
}

local Tutorial = {}

-- Analytics names of the 8 onboarding funnel steps, by step number.
Tutorial.StepNames = {
	"Spawned",
	"Planted",
	"FirstShatter",
	"OpenedShop",
	"BoughtSeed",
	"PlantedTwo",
	"FirstMutation",
	"TutorialDone",
}

-- Steps the client may report with TutorialAction (the others are advanced by the server).
Tutorial.ClientSteps = { [4] = true, [8] = true }

-- Plants needed for step 6 (PlantedTwo): the first crystal plus 2 more.
local PLANTS_FOR_STEP_6 = 3

-- True while the tutorial is running.
function Tutorial.isActive(tutorial: TutorialData): boolean
	return tutorial.Done ~= true
end

-- True for a profile that never started the tutorial but has already played (shattered at least once):
-- it was made before the tutorial existed, so it is marked done without funnel events.
function Tutorial.shouldSkip(tutorial: TutorialData, shatters: number): boolean
	return tutorial.Done ~= true and tutorial.Step == 0 and shatters > 0
end

-- Crystals planted so far (see the header).
function Tutorial.plantsSoFar(shatters: number, occupiedPedestals: number): number
	return shatters + occupiedPedestals
end

-- The tutorial grow time for the very first crystal, or nil. plantsBefore = plants before this one.
function Tutorial.growOverride(tutorial: TutorialData, plantsBefore: number, tutorialSeconds: number): number?
	if Tutorial.isActive(tutorial) and tutorial.Step <= 1 and plantsBefore == 0 then
		return tutorialSeconds
	end
	return nil
end

-- "Glowing" when the plant being made is plant number guaranteedAt (3) during the tutorial, else nil.
function Tutorial.forcedMutation(tutorial: TutorialData, plantsBefore: number, guaranteedAt: number): string?
	if Tutorial.isActive(tutorial) and plantsBefore + 1 == guaranteedAt then
		return "Glowing"
	end
	return nil
end

-- Extra coins for the first shatter of the tutorial (the shatter that moves step 2 to 3), else 0.
function Tutorial.bonusCoins(tutorial: TutorialData, bonus: number): number
	if Tutorial.isActive(tutorial) and tutorial.Step == 2 then
		return bonus
	end
	return 0
end

-- Applies one event and returns (newStep, stepsReached, done). stepsReached lists every step newly reached, in
-- order, so each is logged once; it is empty when nothing changes. The input table is not modified.
-- Events:
--   "Load"                      step 0 -> 1
--   "Plant"   (info.plantsAfter) step 1 -> 2; step 5 -> 6 once plantsAfter >= 3
--   "Shatter" (info.mutation)    step 2 -> 3; step 6 -> 7 for a crystal with a mutation
--   "BuySeed"                   step 3 or 4 -> 5 (also logging 4 if the purchase arrived first)
--   "Action"  (info.step)        client report: 3 -> 4, or 7 -> 8 (which finishes the tutorial); anything else is refused
function Tutorial.advance(
	tutorial: TutorialData,
	event: string,
	info: { [string]: any }?
): (number, { number }, boolean)
	local step = tutorial.Step
	if not Tutorial.isActive(tutorial) then
		return step, {}, true
	end
	local details = info or {}

	local function reach(...: number): (number, { number }, boolean)
		local steps = { ... }
		local last = steps[#steps]
		return last, steps, last == #Tutorial.StepNames
	end

	if event == "Load" then
		if step == 0 then
			return reach(1)
		end
	elseif event == "Plant" then
		if step == 1 then
			return reach(2)
		elseif step == 5 and type(details.plantsAfter) == "number" and details.plantsAfter >= PLANTS_FOR_STEP_6 then
			return reach(6)
		end
	elseif event == "Shatter" then
		if step == 2 then
			return reach(3)
		elseif step == 6 and type(details.mutation) == "string" and details.mutation ~= "None" then
			return reach(7)
		end
	elseif event == "BuySeed" then
		if step == 3 then
			return reach(4, 5)
		elseif step == 4 then
			return reach(5)
		end
	elseif event == "Action" then
		local wanted = details.step
		if type(wanted) == "number" and Tutorial.ClientSteps[wanted] and wanted == step + 1 then
			return reach(wanted)
		end
	end
	return step, {}, false
end

return Tutorial
