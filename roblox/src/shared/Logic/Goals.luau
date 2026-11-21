--!strict
-- Pure daily-goal logic: drawing today's goals from the pool, adding events to their progress and
-- deciding when a goal or the daily bonus may be claimed. The caller passes today's date and the rng.

-- One goal as stored on the profile: the pool Id, the progress so far and whether it is paid out.
export type Goal = {
	Id: string,
	Progress: number,
	Claimed: boolean,
}

-- Today's goal board.
export type DailyGoals = {
	Date: string,
	Goals: { Goal },
	BonusClaimed: boolean,
}

-- One entry of the goal pool, mirroring Config/Progression.GoalPool.
export type PoolGoal = {
	Id: string,
	Target: number,
}

local Goals = {}

-- Event name -> goal Id, so gameplay code never has to hardcode an Id string.
Goals.EventGoal = {
	Shatter = "Shatter20",
	PlantUncommon = "PlantUncommon5",
	Mutation = "FindMutation",
	Coins = "Earn5000",
	Upgrade = "BuyUpgrade",
	ShatterBig = "ShatterBig",
} :: { [string]: string }

-- Fills `dailyGoals` with today's draw, in place. Returns the same table and whether it was rerolled.
-- A board that already belongs to today and holds a full draw is left untouched.
function Goals.ensureToday(
	dailyGoals: DailyGoals,
	today: string,
	pool: { PoolGoal },
	count: number,
	rng: () -> number
): (DailyGoals, boolean)
	local wanted = math.min(count, #pool)
	if dailyGoals.Date == today and #dailyGoals.Goals == wanted then
		return dailyGoals, false
	end

	-- Copy the pool indices into a scratch list, then swap each slot with a random one from the
	-- untouched tail (partial Fisher-Yates). `pool` itself is never reordered.
	local order: { number } = table.create(#pool)
	for index = 1, #pool do
		order[index] = index
	end

	local picked: { Goal } = table.create(wanted)
	for slot = 1, wanted do
		local remaining = #pool - slot + 1
		-- The clamp guards against an rng that returns exactly 1.
		local pick = math.clamp(slot + math.floor(rng() * remaining), slot, #pool)
		order[slot], order[pick] = order[pick], order[slot]
		local drawn = pool[order[slot]]
		picked[slot] = { Id = drawn.Id, Progress = 0, Claimed = false }
	end

	dailyGoals.Date = today
	dailyGoals.BonusClaimed = false
	dailyGoals.Goals = picked
	return dailyGoals, true
end

-- Adds `amount` of the matching goal to every unclaimed goal drawn for `eventName`.
-- Returns the changed indexes, ascending. Progress is never capped, so it may pass the target.
function Goals.track(dailyGoals: DailyGoals, eventName: string, amount: number): { number }
	local goalId = Goals.EventGoal[eventName]
	if goalId == nil or amount <= 0 then
		return {}
	end

	local changed = {}
	for index, goal in dailyGoals.Goals do
		if goal.Id == goalId and not goal.Claimed then
			goal.Progress += amount
			table.insert(changed, index)
		end
	end
	return changed
end

-- Whether the goal at `index` is unclaimed, still in the pool, and has reached that entry's Target.
function Goals.canClaim(dailyGoals: DailyGoals, index: number, pool: { PoolGoal }): boolean
	local goal = dailyGoals.Goals[index]
	if goal == nil or goal.Claimed then
		return false
	end
	for _, entry in pool do
		if entry.Id == goal.Id then
			return goal.Progress >= entry.Target
		end
	end
	return false
end

-- Whether every goal of the day is claimed and the bonus has not been paid out yet.
function Goals.canClaimBonus(dailyGoals: DailyGoals): boolean
	if #dailyGoals.Goals == 0 or dailyGoals.BonusClaimed then
		return false
	end
	for _, goal in dailyGoals.Goals do
		if not goal.Claimed then
			return false
		end
	end
	return true
end

return Goals
