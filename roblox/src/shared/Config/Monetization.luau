--!strict
-- Monetization tuning (passes, products, ads, luck boost); tuned after launch.
-- Ids are 0 placeholders, filled in after creating the items in the Creator Dashboard.
-- DefaultPrice is only an analytics label; the UI must read live prices with GetProductInfo.

export type Pass = {
	Id: number,
	DefaultPrice: number,
	GrowMult: number?,
}

export type Product = {
	Id: number,
	DefaultPrice: number,
	MaxSeconds: number?,
	Mult: number?,
	Count: number?,
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

export type MonetizationConfig = {
	Passes: { [string]: Pass },
	Products: { [string]: Product },
	Ads: AdsConfig,
	LuckBoost: LuckBoostConfig,
	ReceiptHistory: number,
}

local Monetization: MonetizationConfig = {
	Passes = {
		FastGrow = { Id = 0, DefaultPrice = 249, GrowMult = 0.5 },
		DoubleCoins = { Id = 0, DefaultPrice = 199 },
		ExtraPedestals = { Id = 0, DefaultPrice = 149 },
		AutoShatter = { Id = 0, DefaultPrice = 299 },
		VIP = { Id = 0, DefaultPrice = 99 },
	},
	Products = {
		InstantGrowS = { Id = 0, DefaultPrice = 9, MaxSeconds = 900 },
		InstantGrowM = { Id = 0, DefaultPrice = 29, MaxSeconds = 7200 },
		InstantGrowL = { Id = 0, DefaultPrice = 59 },
		GrowAll = { Id = 0, DefaultPrice = 99 },
		LuckBoost = { Id = 0, DefaultPrice = 25 },
		CoinPouchS = { Id = 0, DefaultPrice = 19, Mult = 5 },
		CoinPouchM = { Id = 0, DefaultPrice = 99, Mult = 30 },
		CoinPouchL = { Id = 0, DefaultPrice = 249, Mult = 100 },
		SeedBundle = { Id = 0, DefaultPrice = 39, Count = 3 },
		StarterPack = { Id = 0, DefaultPrice = 49 },
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
}

return Monetization
