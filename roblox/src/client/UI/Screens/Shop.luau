--!strict
-- Shop.luau - the seed shop panel: one card per seed in Config.Seeds, bought one or five at a time.
-- Every card is built once in new(); Update only rewrites texts, colours and visibility in place.
-- A card above the player's HighestUnlockedTier shows a dark silhouette and a "shatter a X to unlock" line.

-- Pixel layout of a single 150x150 shop card.
local CARD_SIZE = 150
local GRID_PADDING = 8 -- gap between neighbouring cards
local CONTENT_PADDING = 4 -- inset between the scrolling frame and the grid
local SIDE_PAD = 6 -- left/right text inset inside a card
local SWATCH_SIZE = 36
local SWATCH_X = 8
local SWATCH_Y = 8
local NAME_X = 50
local NAME_Y = 6
local NAME_W_INSET = 56 -- name width is 1 scale minus this
local NAME_H = 22
local GROW_Y = 28
local GROW_H = 16
local OWNED_Y = 50
local OWNED_H = 18
local PRICE_Y = 70
local PRICE_H = 22
local BUTTON_Y = 96
local BUTTON_H = 48
local BUTTON_INSET = 6 -- button width is 0.5 scale minus this
local BUTTON_MARGIN = 4
local LOCK_Y = 70
local LOCK_H = 44
local SCROLLBAR = 6

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
	Cards: { [string]: Frame },
}

-- The parts of one card that Update rewrites in place.
type CardParts = {
	Frame: Frame,
	Swatch: Frame,
	Grow: TextLabel,
	Owned: TextLabel,
	Price: TextLabel,
	Lock: TextLabel,
	Buy: TextButton,
	BuyFive: TextButton,
}

local Shop = {}

-- Builds the shop inside ctx.Gui and returns the standard screen table plus the card lookup.
function Shop.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local COLORS = Theme.Colors

	-- Guards every snapshot read: the server may send partial state while a profile is loading.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	-- Reads a number field, falling back when the snapshot is missing it.
	local function num(value: any, fallback: number): number
		if typeof(value) == "number" then
			return value
		end
		return fallback
	end

	-- Reads a hex colour, falling back for a malformed seed entry.
	local function hexOr(value: any, fallback: any): string
		if typeof(value) == "string" then
			return value
		end
		if typeof(fallback) == "string" then
			return fallback
		end
		return COLORS.Muted
	end

	-- The rarity stroke colour of a seed, read through the Rarity palette.
	local function rarityHex(seed: any): string
		local rarity = if isTable(seed) then COLORS.Rarity[seed.Rarity] else nil
		return hexOr(rarity, COLORS.Common)
	end

	-- Display name of the seed one tier below `tier`, used by the locked-card hint.
	local function previousSeedName(tier: number): string
		local seeds = ctx.Config.Seeds
		if not isTable(seeds) then
			return ""
		end
		for _, other in seeds do
			if isTable(other) and typeof(other.Id) == "string" and num(other.Tier, -1) == tier - 1 then
				-- The key is built in a local so the screens test can still check every literal key.
				local key = "Seed." .. other.Id
				return Strings.get(key)
			end
		end
		return ""
	end

	local root, content = Components.panel({
		Title = Strings.get("Shop.Title"),
		Size = UDim2.fromScale(0.78, 0.9),
		Name = "Shop",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Shop")
		end,
	})

	-- 1. The scrolling grid that holds every seed card, rows filling top to bottom.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ScrollBarThickness = SCROLLBAR
	scroll.Active = true

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_SIZE, CARD_SIZE)
	grid.CellPadding = UDim2.fromOffset(GRID_PADDING, GRID_PADDING)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, CONTENT_PADDING)
	padding.PaddingBottom = UDim.new(0, CONTENT_PADDING)
	padding.PaddingLeft = UDim.new(0, CONTENT_PADDING)
	padding.PaddingRight = UDim.new(0, CONTENT_PADDING)
	padding.Parent = scroll

	scroll.Parent = content

	-- Fires the BuySeed remote for one card; the server validates price, tier and bag size.
	local function buy(seedId: string, qty: number)
		ctx.Remotes:WaitForChild("BuySeed"):FireServer(seedId, qty)
	end

	-- Cards and the parts Update touches, keyed by seed id.
	local cards: { [string]: CardParts } = {}
	local cardFrames: { [string]: Frame } = {}

	-- Builds one 150x150 card: swatch, name, grow time, owned count, price and the two buy buttons.
	local function buildCard(seed: any): CardParts?
		if not isTable(seed) or typeof(seed.Id) ~= "string" then
			return nil
		end

		local seedId = seed.Id
		local tier = num(seed.Tier, 1)

		local frame = Instance.new("Frame")
		frame.Name = seedId
		frame.Size = UDim2.fromOffset(CARD_SIZE, CARD_SIZE)
		frame.LayoutOrder = tier
		frame.BackgroundColor3 = Theme.color(COLORS.PanelLight)
		frame.BorderSizePixel = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = frame

		-- The stroke carries the seed's rarity colour, so tiers read at a glance.
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = Theme.color(rarityHex(seed))
		stroke.Parent = frame

		-- The round colour chip; a locked seed turns it into a dark silhouette.
		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.Position = UDim2.fromOffset(SWATCH_X, SWATCH_Y)
		swatch.Size = UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE)
		swatch.BackgroundColor3 = Theme.color(hexOr(seed.ColorHex, COLORS.Muted))
		swatch.BorderSizePixel = 0

		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(0.5, 0)
		swatchCorner.Parent = swatch

		swatch.Parent = frame

		local nameKey = "Seed." .. seedId

		Components.label({
			Name = "SeedName",
			Text = Strings.get(nameKey),
			Size = UDim2.new(1, -NAME_W_INSET, 0, NAME_H),
			Position = UDim2.fromOffset(NAME_X, NAME_Y),
			TextSize = 16,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local grow = Components.label({
			Name = "Grow",
			Text = "",
			Size = UDim2.new(1, -(NAME_X + SIDE_PAD), 0, GROW_H),
			Position = UDim2.fromOffset(NAME_X, GROW_Y),
			TextSize = 13,
			Color = COLORS.Muted,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local owned = Components.label({
			Name = "Owned",
			Text = "",
			Size = UDim2.new(1, -SIDE_PAD * 2, 0, OWNED_H),
			Position = UDim2.fromOffset(SIDE_PAD, OWNED_Y),
			TextSize = 14,
			Color = COLORS.Muted,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local price = Components.label({
			Name = "Price",
			Text = "",
			Size = UDim2.new(1, -SIDE_PAD * 2, 0, PRICE_H),
			Position = UDim2.fromOffset(SIDE_PAD, PRICE_Y),
			TextSize = 17,
			Color = COLORS.Gold,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		-- The lock hint replaces the price, owned count and buttons above the player's tier.
		local lock = Components.label({
			Name = "Lock",
			Text = Strings.get("Toast.SeedLocked", { prev = previousSeedName(tier) }),
			Size = UDim2.new(1, -SIDE_PAD * 2, 0, LOCK_H),
			Position = UDim2.fromOffset(SIDE_PAD, LOCK_Y),
			TextSize = 13,
			Color = COLORS.Muted,
			Parent = frame,
		})
		lock.Visible = false

		local buyButton = Components.button({
			Name = "Buy",
			Text = Strings.get("Shop.Buy"),
			Size = UDim2.new(0.5, -BUTTON_INSET, 0, BUTTON_H),
			Position = UDim2.fromOffset(BUTTON_MARGIN, BUTTON_Y),
			Color = COLORS.Good,
			TextColor = COLORS.Bg,
			TextSize = 18,
			OnClick = function()
				buy(seedId, 1)
			end,
			Parent = frame,
		})

		local buyFiveButton = Components.button({
			Name = "BuyFive",
			Text = Strings.get("Shop.BuyFive"),
			Size = UDim2.new(0.5, -BUTTON_INSET, 0, BUTTON_H),
			Position = UDim2.new(0.5, BUTTON_MARGIN, 0, BUTTON_Y),
			Color = COLORS.Good,
			TextColor = COLORS.Bg,
			TextSize = 18,
			OnClick = function()
				buy(seedId, 5)
			end,
			Parent = frame,
		})

		frame.Parent = scroll

		cardFrames[seedId] = frame
		return {
			Frame = frame,
			Swatch = swatch,
			Grow = grow,
			Owned = owned,
			Price = price,
			Lock = lock,
			Buy = buyButton,
			BuyFive = buyFiveButton,
		}
	end

	-- Builds every card once, in Config.Seeds order (already sorted by tier).
	local seeds = ctx.Config.Seeds
	if isTable(seeds) then
		for _, seed in seeds do
			local parts = buildCard(seed)
			if parts and isTable(seed) and typeof(seed.Id) == "string" then
				cards[seed.Id] = parts
			end
		end
	end

	-- Rewrites texts, colours and visibility of every card from a snapshot; never rebuilds or closes.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local coins = num(state.Coins, 0)
		local highest = num(state.HighestUnlockedTier, 1)
		local lampLevel = num(state.LampLevel, 0)
		local lampStep = num(ctx.Config.Economy and ctx.Config.Economy.LampStep, 0)
		local bag = if isTable(state.SeedBag) then state.SeedBag else {}

		if not isTable(seeds) then
			return
		end

		for _, seed in seeds do
			if isTable(seed) and typeof(seed.Id) == "string" then
				local parts = cards[seed.Id]
				if parts then
					local tier = num(seed.Tier, 1)
					local price = num(seed.Price, 0)
					local locked = tier > highest

					parts.Swatch.BackgroundColor3 =
						Theme.color(if locked then COLORS.Bg else hexOr(seed.ColorHex, COLORS.Muted))
					parts.Grow.Visible = not locked
					parts.Owned.Visible = not locked
					parts.Price.Visible = not locked
					parts.Buy.Visible = not locked
					parts.BuyFive.Visible = not locked
					parts.Lock.Visible = locked

					if not locked then
						local growText = Theme.Icons.Time
							.. " "
							.. ctx.Logic.Format.countdown(
								ctx.Logic.Growth.growSeconds(num(seed.GrowSeconds, 0), lampLevel, lampStep)
							)
						parts.Grow.Text = growText
						parts.Owned.Text = Strings.get("Shop.Owned", { count = num(bag[seed.Id], 0) })
						parts.Price.Text = Theme.Icons.Coins .. " " .. ctx.Logic.Format.compact(price)
						-- A greyed price tells the player they cannot afford it yet; the button still works.
						parts.Price.TextColor3 = Theme.color(if coins >= price then COLORS.Gold else COLORS.Muted)
					end
				end
			end
		end
	end

	local screen: Screen = {
		Root = root,
		Cards = cardFrames,
		Open = function(_args: any?)
			refresh(ctx.State:Get())
			root.Visible = true
		end,
		Close = function()
			root.Visible = false
		end,
		Update = function(snapshot: any)
			refresh(snapshot)
		end,
		IsOpen = function(): boolean
			return root.Visible
		end,
	}

	-- Sensible defaults until the first snapshot arrives (everything above tier 1 reads as locked).
	refresh(nil)

	return screen
end

return Shop
