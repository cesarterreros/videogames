--!strict
-- Progression tuning (login streak, daily goal pool, codex bonus, tutorial); tuned after launch.

export type StreakDay = {
	Coins: number?,
	Seed: string?,
	Count: number?,
}

export type Goal = {
	Id: string,
	Target: number,
}

export type TutorialConfig = {
	GrowSeconds: number,
	BonusCoins: number,
	GuaranteedGlowingOnShatter: number,
}

export type ProgressionConfig = {
	Streak: { StreakDay },
	GoalPool: { Goal },
	GoalsPerDay: number,
	CodexBonus: number,
	GoalRewardValueMult: number,
	Tutorial: TutorialConfig,
}

local Progression: ProgressionConfig = {
	Streak = {
		{ Coins = 100 }, -- day 1
		{ Coins = 250 }, -- day 2
		{ Seed = "Citrine", Count = 1 }, -- day 3
		{ Coins = 1000 }, -- day 4
		{ Coins = 2500 }, -- day 5
		{ Coins = 5000 }, -- day 6
		{ Seed = "Emerald", Count = 1 }, -- day 7
	},
	GoalPool = {
		{ Id = "Shatter20", Target = 20 },
		{ Id = "PlantUncommon5", Target = 5 },
		{ Id = "FindMutation", Target = 1 },
		{ Id = "Earn5000", Target = 5000 },
		{ Id = "BuyUpgrade", Target = 1 },
		{ Id = "ShatterBig", Target = 1 },
	},
	GoalsPerDay = 3,
	CodexBonus = 0.10,
	-- A claimed daily goal pays this × BaseValue of the player's highest unlocked seed.
	GoalRewardValueMult = 10,
	Tutorial = {
		GrowSeconds = 8,
		BonusCoins = 50,
		GuaranteedGlowingOnShatter = 3,
	},
}

return Progression
