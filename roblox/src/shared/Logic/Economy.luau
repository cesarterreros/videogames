--!strict
-- Pure shop economy math: seed lookup, buy checks, upgrade costs, payout multipliers and goal rewards.
-- Every value arrives as an argument, so nothing here reads the clock or touches Roblox APIs.

local Economy = {}

-- Shape of one seed row, mirroring Config/Seeds; declared here so callers can build fixtures freely.
export type Seed = {
	Id: string,
	Tier: number,
	Rarity: string,
	Price: number,
	GrowSeconds: number,
	BaseValue: number,
	BaseCarats: number,
	ColorHex: string,
}

-- Seed with the matching Id, or nil when the id is unknown.
function Economy.seedById(seeds: { Seed }, id: string): Seed?
	for _, seed in seeds do
		if seed.Id == id then
			return seed
		end
	end
	return nil
end

-- Whether `qty` of a seed may be bought: the tier lock is checked first, then the total price.
function Economy.canBuySeed(seed: Seed, highestTier: number, coins: number, qty: number): (boolean, string?)
	if seed.Tier > highestTier then
		return false, "Locked"
	end
	local cost = seed.Price * qty
	if coins < cost then
		return false, "Coins"
	end
	return true, nil
end

-- Cost of the next display pedestal, or nil once all `maxCoin` pedestals are already unlocked.
function Economy.nextPedestalCost(unlocked: number, costs: { [number]: number }, maxCoin: number): number?
	local nextIndex = unlocked + 1
	if nextIndex > maxCoin then
		return nil
	end
	return costs[nextIndex]
end

-- Cost of the next grow lamp level, or nil when the ladder is finished.
function Economy.nextLampCost(level: number, costs: { number }): number?
	return costs[level + 1]
end

-- Coin multiplier for a shatter: the codex bonus applies only on a complete codex, the friend bonus always.
function Economy.shatterCoinMult(codexComplete: boolean, codexBonus: number, friendBonus: number): number
	local codexMult = if codexComplete then 1 + codexBonus else 1
	return codexMult * (1 + friendBonus)
end

-- Coin reward for a goal that targets `highestTier`: the seed of that tier, else the closest lower tier,
-- else the lowest seed in the table when every seed sits above the goal.
-- The tiny 1e-9 nudge keeps float products from flooring down a whole coin.
function Economy.goalReward(seeds: { Seed }, highestTier: number, mult: number): number
	for _, seed in seeds do
		if seed.Tier == highestTier then
			return math.floor(mult * seed.BaseValue + 1e-9)
		end
	end

	local below: Seed? = nil
	for _, seed in seeds do
		if seed.Tier < highestTier and (below == nil or seed.Tier > below.Tier) then
			below = seed
		end
	end

	local chosen = below
	if chosen == nil then
		for _, seed in seeds do
			if chosen == nil or seed.Tier < chosen.Tier then
				chosen = seed
			end
		end
	end

	local picked = chosen
	if picked == nil then
		return 0
	end
	return math.floor(mult * picked.BaseValue + 1e-9)
end

-- Id of the seed handed out as a surprise: one tier above the player, capped at the top of the ladder.
-- An empty table gives "".
function Economy.surpriseSeedId(seeds: { Seed }, highestTier: number): string
	-- Tiers are positive, so 0 is a safe floor while scanning for the top of the ladder.
	local maxTier = 0
	for _, seed in seeds do
		if seed.Tier > maxTier then
			maxTier = seed.Tier
		end
	end

	local target = math.min(highestTier + 1, maxTier)
	for _, seed in seeds do
		if seed.Tier == target then
			return seed.Id
		end
	end
	return ""
end

-- Coins in a Coin Pouch: `mult` × the base value of the player's highest unlocked seed (same lookup and fallback as
-- goalReward), worked out when the receipt is processed.
function Economy.coinPouchAmount(seeds: { Seed }, highestTier: number, mult: number): number
	return Economy.goalReward(seeds, highestTier, mult)
end

return Economy
