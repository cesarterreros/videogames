--!strict
-- Every remote in the game. The server creates them from this list; handlers validate Args. Never add InvokeClient usage.
return {
	StateSync = { Kind = "Event", Direction = "ToClient" },
	Toast = { Kind = "Event", Direction = "ToClient" },
	Plant = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "int", min = 1, max = 13 },
			{ kind = "enum", valuesFrom = "SeedIds" },
		},
	},
	Shatter = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "int", min = 1, max = 13 },
		},
	},
	ShatterAll = {
		Kind = "Event",
		Direction = "ToServer",
		Rate = 2,
		Burst = 3,
		Args = {},
	},
	ShatterResult = { Kind = "Event", Direction = "ToClient" },
	BuySeed = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "enum", valuesFrom = "SeedIds" },
			{ kind = "enum", values = { 1, 5 } },
		},
	},
	BuyUpgrade = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "enum", values = { "Pedestal", "Lamp" } },
		},
	},
	ClaimDaily = {
		Kind = "Event",
		Direction = "ToServer",
		Rate = 1,
		Burst = 2,
		Args = {},
	},
	ClaimGoal = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "enum", values = { 1, 2, 3, "Bonus" } },
		},
	},
	Announce = { Kind = "Event", Direction = "ToClient" },
	TutorialAction = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "int", min = 1, max = 8 },
		},
	},
	SetSetting = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "enum", values = { "AutoShatter", "Music" } },
			{ kind = "bool" },
		},
	},
	-- Cave brightness level; must match the preset names in Config/Lighting (checked by Config.spec).
	SetBrightness = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "enum", values = { "Dark", "Normal", "Bright" } },
		},
	},
	-- Batch 5: the session's one popup offer ({ kind = "StarterPack" | "DoubleCoins" }), and the player's policy
	-- flags the client needs ({ paidRandomItemsRestricted = bool }), both sent by the server.
	Offer = { Kind = "Event", Direction = "ToClient" },
	PolicyInfo = { Kind = "Event", Direction = "ToClient" },
	RequestInstantGrow = {
		Kind = "Function",
		Direction = "ToServer",
		Rate = 2,
		Burst = 4,
		Args = {
			{ kind = "int", min = 1, max = 13 },
		},
	},
	UseToken = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			{ kind = "int", min = 1, max = 13 },
		},
	},
	RequestAd = {
		Kind = "Event",
		Direction = "ToServer",
		Rate = 1,
		Burst = 2,
		Args = {
			{ kind = "enum", values = { "FinishNow", "Luck", "CoinPouch" } },
			{ kind = "int", min = 1, max = 13, optional = true },
		},
	},
}
