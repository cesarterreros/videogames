--!strict
-- SeedPicker.luau - the modal seed picker that opens when the player taps an empty unlocked pedestal.
-- One card per owned seed, in Config.Seeds order (already sorted by tier), with the count in the bag.
-- Tapping a card fires Plant(pedestalIndex, seedId) and closes the panel; an empty bag offers the Shop.

-- Pixel layout for the horizontal card strip.
local CARD_W = 110
local CARD_H = 130
local GAP = 8 -- gap between neighbouring cards
local SWATCH_SIZE = 40
local SWATCH_Y = 8
local NAME_Y = 54
local COUNT_Y = 84
local LINE_H = 26
local EMPTY_LABEL_Y = 0.2 -- scale fraction of the content height
local EMPTY_LABEL_H = 40
local SHOP_W = 160
local SHOP_H = 52

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

local SeedPicker = {}

-- Builds the picker inside ctx.Gui and returns the standard screen table.
function SeedPicker.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local COLORS = Theme.Colors

	-- Guards every snapshot read: the server may send partial state while a profile is loading.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	-- Reads a hex colour, falling back to the plain text colour for a malformed seed entry.
	local function hexOr(value: any, fallback: string): string
		if typeof(value) == "string" then
			return value
		end
		return fallback
	end

	local root, content = Components.panel({
		Title = Strings.get("SeedPicker.Title"),
		Size = UDim2.fromScale(0.6, 0.8), -- tall enough for the 130 px cards on a phone
		Name = "SeedPicker",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("SeedPicker")
		end,
	})

	-- 1. The horizontal strip of seed cards, scrolling sideways when the bag holds many kinds.
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Strip"
	strip.Size = UDim2.fromScale(1, 1)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new(0, 0, 0, 0)
	strip.ScrollBarThickness = 6
	strip.Active = true

	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, GAP)
	stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Parent = strip

	strip.Parent = content

	-- 2. The empty-bag state: a hint line and a shortcut to the Shop. Both stay hidden until needed.
	local emptyLabel = Components.label({
		Name = "Empty",
		Text = Strings.get("SeedPicker.Empty"),
		Size = UDim2.new(1, 0, 0, EMPTY_LABEL_H),
		Position = UDim2.fromScale(0, EMPTY_LABEL_Y),
		Color = COLORS.Muted,
		Parent = content,
	})
	emptyLabel.Visible = false

	local shopButton = Components.button({
		Name = "Shop",
		Icon = Theme.Icons.Shop,
		Text = Strings.get("Hud.Shop"),
		Size = UDim2.fromOffset(SHOP_W, SHOP_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, EMPTY_LABEL_Y, EMPTY_LABEL_H + GAP),
		Color = COLORS.Gold,
		TextColor = COLORS.Bg,
		OnClick = function()
			ctx.UI:Open("Shop")
		end,
		Parent = content,
	})
	shopButton.Visible = false

	-- The pedestal that opened the picker; kept from Open so Update never loses it.
	local pedestalIndex: number? = nil

	-- Plants the tapped seed into the pedestal that opened the picker, then closes the panel.
	local function plant(seedId: string)
		local index = pedestalIndex
		if index == nil or not root.Visible then
			return
		end
		ctx.Remotes:WaitForChild("Plant"):FireServer(index, seedId)
		ctx.UI:Close("SeedPicker")
	end

	-- Cards and their count labels, keyed by seed id so Update can refresh counts in place.
	local cardsById: { [string]: TextButton } = {}
	local countLabels: { [string]: TextLabel } = {}

	local function clearCards()
		for _, card in cardsById do
			card:Destroy()
		end
		table.clear(cardsById)
		table.clear(countLabels)
	end

	-- Builds one 110x130 seed card: colour swatch, seed name and how many are left in the bag.
	local function buildCard(seed: any, count: number)
		local card = Components.button({
			Name = seed.Id,
			Text = "",
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			LayoutOrder = if typeof(seed.Tier) == "number" then seed.Tier else 0,
			OnClick = function()
				plant(seed.Id)
			end,
			Parent = strip,
		})

		-- The stroke carries the seed's rarity colour, so tiers read at a glance.
		local rarityColor = COLORS.Rarity[seed.Rarity]
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.color(hexOr(rarityColor, hexOr(COLORS.Common, COLORS.Text)))
		end

		local swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.AnchorPoint = Vector2.new(0.5, 0)
		swatch.Position = UDim2.new(0.5, 0, 0, SWATCH_Y)
		swatch.Size = UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE)
		swatch.BackgroundColor3 = Theme.color(hexOr(seed.ColorHex, COLORS.Text))
		swatch.BorderSizePixel = 0

		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(0.5, 0)
		swatchCorner.Parent = swatch

		swatch.Parent = card

		-- The key is built in a local so the screens test can still check every literal key in en.luau.
		local nameKey = "Seed." .. seed.Id

		Components.label({
			Name = "SeedName",
			Text = Strings.get(nameKey),
			Size = UDim2.new(1, -8, 0, LINE_H),
			Position = UDim2.fromOffset(4, NAME_Y),
			TextSize = 15,
			Parent = card,
		})

		local countLabel = Components.label({
			Name = "Count",
			Text = Strings.get("SeedPicker.Count", { count = count }),
			Size = UDim2.new(1, -8, 0, LINE_H),
			Position = UDim2.fromOffset(4, COUNT_Y),
			TextSize = 18,
			Color = COLORS.Gold,
			Parent = card,
		})

		cardsById[seed.Id] = card
		countLabels[seed.Id] = countLabel
	end

	-- Writes a new count into an existing card without rebuilding the strip.
	local function setCount(seedId: string, count: number)
		local countLabel = countLabels[seedId]
		if countLabel then
			countLabel.Text = Strings.get("SeedPicker.Count", { count = count })
		end
	end

	-- Toggles between the card strip and the empty-bag hint.
	local function showEmpty(empty: boolean)
		strip.Visible = not empty
		emptyLabel.Visible = empty
		shopButton.Visible = empty
	end

	-- The owned-seed signature of the last refresh: cards rebuild only when the *set* of seeds changes.
	local signature: string? = nil

	-- Rebuilds the cards (or just the counts) from a snapshot of the player's state.
	local function refresh(snapshot: any)
		local bag = if isTable(snapshot) and isTable(snapshot.SeedBag) then snapshot.SeedBag else {}
		local seeds = ctx.Config.Seeds
		local owned: { any } = {}
		local ids: { string } = {}

		if isTable(seeds) then
			for _, seed in seeds do
				if isTable(seed) and typeof(seed.Id) == "string" then
					local count = bag[seed.Id]
					if typeof(count) == "number" and count >= 1 then
						table.insert(owned, { Seed = seed, Count = count })
						table.insert(ids, seed.Id)
					end
				end
			end
		end

		local nextSignature = table.concat(ids, "|")
		if nextSignature ~= signature then
			signature = nextSignature
			clearCards()
			for _, entry in owned do
				buildCard(entry.Seed, entry.Count)
			end
		else
			for _, entry in owned do
				setCount(entry.Seed.Id, entry.Count)
			end
		end

		showEmpty(#owned == 0)
	end

	local screen: Screen = {
		Root = root,
		Open = function(args: any?)
			pedestalIndex = if typeof(args) == "number" then args else nil
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

	-- Start on the empty-bag hint; nothing is known about the bag until the first snapshot arrives.
	showEmpty(true)

	return screen
end

return SeedPicker
