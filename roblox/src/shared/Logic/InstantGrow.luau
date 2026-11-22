--!strict
-- Pure instant-grow helpers: which shop product a grow timer maps to, and which
-- owned token to spend on it. All timing values come from config, so this is
-- plain arithmetic with no APIs and no side effects.

export type Tier = "S" | "M" | "L"

local InstantGrow = {}

-- Smallest tier first, so table order is also price order.
InstantGrow.TIERS = { "S", "M", "L" } :: { Tier }

-- Smallest tier that can skip the whole remaining grow time: S up to cfg.S
-- seconds (including 0 or less), M up to cfg.M seconds, L for anything longer.
function InstantGrow.tierFor(secondsLeft: number, cfg: { S: number, M: number }): Tier
	if secondsLeft <= cfg.S then
		return "S"
	end
	if secondsLeft <= cfg.M then
		return "M"
	end
	return "L"
end

-- Developer-product key for a tier, e.g. "InstantGrowM".
function InstantGrow.productKey(tier: Tier): string
	return "InstantGrow" .. tier
end

-- Smallest tier at or above `needed` the player still owns a token for.
-- Missing or non-number counts count as zero; nil when nothing covers `needed`.
function InstantGrow.pickToken(tokens: { S: number, M: number, L: number }, needed: Tier): Tier?
	local start = 1
	for index, tier in InstantGrow.TIERS do
		if tier == needed then
			start = index
			break
		end
	end

	for index = start, #InstantGrow.TIERS do
		local tier = InstantGrow.TIERS[index]
		local count = (tokens :: any)[tier]
		if type(count) == "number" and count > 0 then
			return tier
		end
	end

	return nil
end

return InstantGrow
