--!strict
-- Monetization tuning (passes, products, ads, luck boost); tuned after launch.
-- Pass and product IDs live in IdsByGameId, one table per experience (dev and live are different universes).
-- DefaultPrice is only an analytics label; the UI must read live prices with GetProductInfoAsync.

export type Pass = {
	DefaultPrice: number,
	GrowMult: number?, -- Fast Grow: growth-phase time multiplier
	CoinMult: number?, -- Double Coins: shatter-coin multiplier
}

export type Product = {
	DefaultPrice: number,
	MaxSeconds: number?,
	Mult: number?,
	Count: number?,
	Coins: number?, -- Starter Pack
	SeedId: string?, -- Starter Pack
	LuckMinutes: number?, -- Starter Pack
}

export type AdsConfig = {
	CooldownSeconds: number,
	DailyTotal: number,
	Caps: { [string]: number },
}

export type LuckBoostConfig = {
	Minutes: number,
	MaxBankMinutes: number,
	Mult: number,
	MaxTotalMult: number,
}

export type ItemIds = {
	Passes: { [string]: number },
	Products: { [string]: number },
}

export type MonetizationConfig = {
	Passes: { [string]: Pass },
	Products: { [string]: Product },
	Ads: AdsConfig,
	LuckBoost: LuckBoostConfig,
	ReceiptHistory: number,
	PendingTargetSeconds: number,
	ReceiptSaveTimeoutSeconds: number,
	IdsByGameId: { [number]: ItemIds },
}

local Monetization: MonetizationConfig = {
	Passes = {
		FastGrow = { DefaultPrice = 249, GrowMult = 0.5 },
		DoubleCoins = { DefaultPrice = 199, CoinMult = 2 },
		ExtraPedestals = { DefaultPrice = 149 },
		AutoShatter = { DefaultPrice = 299 },
		VIP = { DefaultPrice = 99 },
	},
	Products = {
		InstantGrowS = { DefaultPrice = 9, MaxSeconds = 900 },
		InstantGrowM = { DefaultPrice = 29, MaxSeconds = 7200 },
		InstantGrowL = { DefaultPrice = 59 },
		GrowAll = { DefaultPrice = 99 },
		LuckBoost = { DefaultPrice = 25 },
		CoinPouchS = { DefaultPrice = 19, Mult = 5 },
		CoinPouchM = { DefaultPrice = 99, Mult = 30 },
		CoinPouchL = { DefaultPrice = 249, Mult = 100 },
		SeedBundle = { DefaultPrice = 39, Count = 3 },
		StarterPack = { DefaultPrice = 49, Coins = 1000, SeedId = "Citrine", Count = 3, LuckMinutes = 30 },
	},
	Ads = {
		CooldownSeconds = 60,
		DailyTotal = 9,
		Caps = {
			FinishNow = 5,
			Luck = 3,
			CoinPouch = 1,
		},
	},
	LuckBoost = {
		Minutes = 15,
		MaxBankMinutes = 60,
		Mult = 2,
		MaxTotalMult = 3,
	},
	ReceiptHistory = 100,
	PendingTargetSeconds = 60, -- how long an Instant Grow prompt (or ad) remembers its crystal
	ReceiptSaveTimeoutSeconds = 15, -- ProcessReceipt waits this long for the save that records the purchase
	-- game.GameId (universe ID, public) -> the IDs created in that experience. Any other experience, or an
	-- unpublished place, gets no IDs, so its monetization stays hidden. The live experience is added at launch.
	IdsByGameId = {
		[10777641396] = { -- Crystal Grove DEV, created through Open Cloud on 2026-11-22
			Passes = {
				FastGrow = 2096118369,
				DoubleCoins = 2092536394,
				ExtraPedestals = 2093706287,
				AutoShatter = 2092686441,
				VIP = 2092878404,
			},
			Products = {
				InstantGrowS = 3734749807,
				InstantGrowM = 3734749816,
				InstantGrowL = 3734749821,
				GrowAll = 3734749828,
				LuckBoost = 3734749833,
				CoinPouchS = 3734749994,
				CoinPouchM = 3734749998,
				CoinPouchL = 3734750007,
				SeedBundle = 3734750013,
				StarterPack = 3734750019,
			},
		},
	},
}

return Monetization
