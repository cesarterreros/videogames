--!strict
-- Theme.luau - the shared look and feel for every client UI screen: palette, font, spacing and emoji icons.
-- Pure data plus a couple of tiny helpers, so it can be required from Lune unit tests: nothing here
-- touches `game`, `Color3`, `Font` or `Enum` at module load time, only inside the helper functions.

local Theme = {}

-- Palette. Every value is a "#RRGGBB" string so the table stays inspectable outside Roblox.
Theme.Colors = {
	Bg = "#14122B",
	Panel = "#221F45",
	PanelLight = "#2E2A5C",
	Text = "#FFFFFF",
	Muted = "#A9A6C9",
	Gold = "#FFD54A",
	Good = "#4CD964",
	Bad = "#FF5A5F",
	Stroke = "#0B0A1A",
	Disabled = "#55527A",
	Rarity = {
		Common = "#E6E9EE",
		Uncommon = "#4CD964",
		Rare = "#3D8BFF",
		Epic = "#B05CFF",
		Legendary = "#FFB020",
	},
}

Theme.Font = "FredokaOne"
Theme.MinTouch = 48 -- px, smallest tappable size
Theme.Corner = 12 -- px
Theme.StrokeThickness = 2

-- Emoji icons (verified to render in Studio). Close uses a bold "X" because "✕" does not render.
Theme.Icons = {
	Coins = "💰",
	WeeklyBest = "🏆",
	MyCave = "🏠",
	Shop = "🛒",
	Upgrades = "⬆️",
	Codex = "📖",
	Daily = "🎁",
	Goals = "🎯",
	Surge = "⚡",
	Odds = "🎲",
	MusicOn = "🔊",
	MusicOff = "🔇",
	Brightness = "☀",
	Time = "⏱",
	Close = "X",
}

-- Parses "#RRGGBB" (or "RRGGBB", any case) into 0..255 integer channels; errors on anything else.
function Theme.rgb(hex: string): (number, number, number)
	local digits = string.match(hex, "^#?(%x%x%x%x%x%x)$")
	if not digits then
		error(string.format('Theme.rgb: expected a hex colour like "#FFD54A", got %q', tostring(hex)), 2)
	end
	local red = tonumber(string.sub(digits, 1, 2), 16) :: number
	local green = tonumber(string.sub(digits, 3, 4), 16) :: number
	local blue = tonumber(string.sub(digits, 5, 6), 16) :: number
	return red, green, blue
end

-- Converts a hex string into a Roblox Color3.
function Theme.color(hex: string): Color3
	local red, green, blue = Theme.rgb(hex)
	return Color3.fromRGB(red, green, blue)
end

-- The single font used by every text object in the game.
function Theme.fontFace(): Font
	return Font.fromEnum(Enum.Font.FredokaOne)
end

return Theme
