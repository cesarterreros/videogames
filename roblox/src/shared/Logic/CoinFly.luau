--!strict
-- Coin-fly helpers: how many coin icons a shatter launches and how the coins split between them.
-- Pure arithmetic only, so the Lune unit tests can load it without a Roblox environment.

local CoinFly = {}

local MIN_ICONS = 6
local MAX_ICONS = 12
local ICONS_PER_DECADE = 1.5

-- True for a real number (not NaN, not +/-infinity).
local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Number of coin icons to fly for a shatter worth `coins`: six for a handful, a dozen for millions.
-- Returns 0 when there is nothing to fly (no coins, NaN or an infinite amount).
function CoinFly.iconCount(coins: number): number
	if not isFinite(coins) or coins <= 0 then
		return 0
	end
	return math.clamp(MIN_ICONS + math.floor(math.log10(coins) * ICONS_PER_DECADE), MIN_ICONS, MAX_ICONS)
end

-- Splits `coins` into `n` whole-number shares, each at least 0, summing to exactly floor(coins) and
-- differing by at most 1. The first shares get the extra coin, so the biggest ones leave first.
-- Returns an empty list when there is nothing to split.
function CoinFly.split(coins: number, n: number): { number }
	local shares: { number } = {}
	local total = math.floor(coins)
	local count = math.floor(n)
	if not isFinite(total) or not isFinite(count) or count <= 0 or total <= 0 then
		return shares
	end
	local base = math.floor(total / count)
	local extra = total - base * count
	for index = 1, count do
		shares[index] = base + if index <= extra then 1 else 0
	end
	return shares
end

return CoinFly
