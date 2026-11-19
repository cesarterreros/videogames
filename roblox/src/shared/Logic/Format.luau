--!strict
-- Player-facing number and text formatting helpers, using only standard Luau.

local Format = {}

-- Magnitude tiers, largest first so the first match wins.
local TIERS = {
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
	{ Value = 1e3, Suffix = "K" },
}

-- Renders an integer tenths count as "whole" or "whole.tenth".
local function formatTenths(whole: number, tenth: number): string
	if tenth == 0 then
		return string.format("%d", whole)
	end
	return string.format("%d.%d", whole, tenth)
end

-- Short human-readable number: 999 -> "999", 12400 -> "12.4K", 2.5e9 -> "2.5B".
function Format.compact(n: number): string
	local negative = n < 0
	local value = math.abs(n)
	local text: string

	if value < 1000 then
		local whole = math.floor(value)
		text = string.format("%d", whole)
		if whole == 0 then
			negative = false
		end
	else
		local divisor, suffix = TIERS[#TIERS].Value, TIERS[#TIERS].Suffix
		for _, tier in TIERS do
			if value >= tier.Value then
				divisor, suffix = tier.Value, tier.Suffix
				break
			end
		end
		-- Truncate (never round up) to one decimal so the display never overstates the value.
		local tenths = math.floor(value / divisor * 10)
		text = formatTenths(math.floor(tenths / 10), tenths % 10) .. suffix
	end

	return if negative then "-" .. text else text
end

-- Carat weight with one rounded decimal and a " ct" suffix: 14.234 -> "14.2 ct".
function Format.carats(x: number): string
	local rounded = math.floor(x * 10 + 0.5) / 10
	return string.format("%.1f ct", rounded)
end

-- Replaces {name} placeholders with tostring(params[name]); unknown names are left as-is.
function Format.interpolate(template: string, params: { [string]: any }?): string
	if params == nil then
		return template
	end
	local lookup = params :: { [string]: any }
	local result = string.gsub(template, "{([%w_]+)}", function(name: string): string
		local value = lookup[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end)
	return result
end

return Format
