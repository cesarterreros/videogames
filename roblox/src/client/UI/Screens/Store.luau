--!strict
-- Store.luau - the monetization panel: game passes, boosts and coin/seed products, grouped in three
-- sections inside one scrolling list. Every card is built once in new(); refresh only rewrites the
-- description and price texts and toggles Visible/enabled. No price is written here: the numbers come
-- live from ctx.Purchase, which also owns the Roblox prompts (this screen never touches a remote).

-- Layout, in pixels inside the content frame.
local HEADER_H = 24
local HEADER_SIZE = 18
local LIST_PAD = 6 -- gap between the sections and their rows
local CARD_W = 140
local CARD_H = 118
local CELL_PAD = 8
local NAME_Y = 6
local NAME_H = 22
local NAME_SIZE = 17
local DESC_Y = 28
local DESC_H = 34
local DESC_SIZE = 12
local BUTTON_H = 48
local BUTTON_SIZE = 18
local BUTTON_BOTTOM = 6
local CARD_SIDE = 16 -- the name and description are the card width minus this
local BUTTON_SIDE = 12
local SCROLLBAR = 6

-- Grow All only earns a card while this many crystals are still growing.
local GROWING_MIN = 5

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One thing the store sells: its kind ("Pass" or "Product") and its config key.
export type Item = {
	Kind: string,
	Key: string,
}

-- One store card: the item it sells, its frame, its two labels and the buy button.
type Card = {
	Item: Item,
	Frame: Frame,
	Name: TextLabel,
	Desc: TextLabel,
	Button: TextButton,
}

-- One list section: its header label and the cards built inside its grid row.
type Section = {
	Header: TextLabel,
	Cards: { Card },
}

type SectionInfo = {
	HeaderKey: string,
	Items: { Item },
}

-- The three sections of the store, in the order they appear top to bottom.
local SECTIONS: { SectionInfo } = {
	{
		HeaderKey = "Store.Passes",
		Items = {
			{ Kind = "Pass", Key = "FastGrow" },
			{ Kind = "Pass", Key = "DoubleCoins" },
			{ Kind = "Pass", Key = "ExtraPedestals" },
			{ Kind = "Pass", Key = "AutoShatter" },
			{ Kind = "Pass", Key = "VIP" },
		},
	},
	{
		HeaderKey = "Store.Boosts",
		Items = {
			{ Kind = "Product", Key = "LuckBoost" },
			{ Kind = "Product", Key = "GrowAll" },
		},
	},
	{
		HeaderKey = "Store.CoinsSeeds",
		Items = {
			{ Kind = "Product", Key = "CoinPouchS" },
			{ Kind = "Product", Key = "CoinPouchM" },
			{ Kind = "Product", Key = "CoinPouchL" },
			{ Kind = "Product", Key = "SeedBundle" },
			{ Kind = "Product", Key = "StarterPack" },
		},
	},
}

local Store = {}

-- Builds the store panel inside ctx.Gui and returns the standard screen table.
function Store.new(ctx: any): Screen
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

	-- One row of ctx.Config.Monetization.Products (an empty table when the config or the key is missing).
	local function product(key: string): any
		local monetization = ctx.Config.Monetization
		local products = if isTable(monetization) then monetization.Products else nil
		local row = if isTable(products) then products[key] else nil
		return if isTable(row) then row else {}
	end

	-- ctx.Config.Monetization.LuckBoost, or an empty table when the config is missing.
	local function luckBoost(): any
		local monetization = ctx.Config.Monetization
		local boost = if isTable(monetization) then monetization.LuckBoost else nil
		return if isTable(boost) then boost else {}
	end

	-- The translated name of one seed; the key depends on the seed, so it is built here first.
	local function seedName(id: any): string
		local seedKey = "Seed." .. tostring(id)
		return Strings.get(seedKey)
	end

	-- The best seed the player can plant right now: the highest tier at or below `tier`.
	local function seedAtTier(tier: number): any
		local seeds = ctx.Config.Seeds
		if not isTable(seeds) then
			return nil
		end
		local best: any = nil
		for _, seed in seeds do
			if isTable(seed) then
				local seedTier = num(seed.Tier, 0)
				if seedTier <= tier and (best == nil or seedTier > num(best.Tier, 0)) then
					best = seed
				end
			end
		end
		return best
	end

	-- Coins in a coin pouch, short: the pouch multiplier times the value of the player's best seed.
	local function pouchCoins(key: string, tier: number): string
		local seeds = ctx.Config.Seeds
		local mult = num(product(key).Mult, 1)
		if not isTable(seeds) then
			return ctx.Logic.Format.compact(0)
		end
		return ctx.Logic.Format.compact(ctx.Logic.Economy.coinPouchAmount(seeds, tier, mult))
	end

	-- The description of one card: static text for passes and Grow All, snapshot figures for the rest.
	local function describe(item: Item, tier: number): string
		local descKey = item.Kind .. "." .. item.Key .. ".Desc"

		if item.Key == "LuckBoost" then
			local boost = luckBoost()
			return Strings.get(descKey, { mult = num(boost.Mult, 1), minutes = num(boost.Minutes, 0) })
		end

		-- The three coin pouches share one description: only the coin amount differs.
		if item.Key == "CoinPouchS" or item.Key == "CoinPouchM" or item.Key == "CoinPouchL" then
			return Strings.get("Product.CoinPouch.Desc", { coins = pouchCoins(item.Key, tier) })
		end

		if item.Key == "SeedBundle" then
			local bundle = product(item.Key)
			local seed = seedAtTier(tier)
			local seedId = if seed ~= nil then seed.Id else nil
			return Strings.get(descKey, { count = num(bundle.Count, 0), seed = seedName(seedId) })
		end

		if item.Key == "StarterPack" then
			local pack = product(item.Key)
			return Strings.get(descKey, {
				coins = ctx.Logic.Format.compact(num(pack.Coins, 0)),
				count = num(pack.Count, 0),
				seed = seedName(pack.SeedId),
				minutes = num(pack.LuckMinutes, 0),
			})
		end

		return Strings.get(descKey)
	end

	-- True while enough crystals are still growing for the Grow All product to be worth a card.
	local function enoughGrowing(state: any, now: number): boolean
		local pedestals = if isTable(state.Pedestals) then state.Pedestals else {}
		local growing = 0
		for _, crystal in pedestals do
			if isTable(crystal) and num(crystal.ReadyAt, 0) > now then
				growing += 1
			end
		end
		return growing >= GROWING_MIN
	end

	-- A card shows only when the experience sells it and its own extra conditions hold.
	local function isVisible(item: Item, state: any, now: number): boolean
		if ctx.Purchase:IsHidden(item.Kind, item.Key) then
			return false
		end
		if item.Key == "GrowAll" then
			return enoughGrowing(state, now)
		end
		if item.Key == "StarterPack" then
			local monetization = if isTable(state.Monetization) then state.Monetization else {}
			return monetization.StarterPackBought ~= true
		end
		return true
	end

	local root, content = Components.panel({
		Title = Strings.get("Store.Title"),
		Size = UDim2.fromScale(0.9, 0.92),
		Name = "Store",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Store")
		end,
	})

	-- One scrolling list holds the three sections; each section is a header above its grid row.
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, LIST_PAD)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	list.Parent = content

	-- Builds one card: name, description and the buy button, all refreshed in place later.
	local function buildCard(item: Item, layoutOrder: number, parent: Frame): Card
		local frame = Instance.new("Frame")
		frame.Name = item.Key
		frame.LayoutOrder = layoutOrder
		frame.BackgroundColor3 = Theme.color(COLORS.PanelLight)
		frame.BorderSizePixel = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = Theme.StrokeThickness
		stroke.Color = Theme.color(COLORS.Stroke)
		stroke.Parent = frame

		-- The name key depends on the item ("Pass.VIP", "Product.GrowAll"), so it is built first.
		local nameKey = item.Kind .. "." .. item.Key
		local name = Components.label({
			Name = "Name",
			Text = Strings.get(nameKey),
			Size = UDim2.new(1, -CARD_SIDE, 0, NAME_H),
			Position = UDim2.fromOffset(8, NAME_Y),
			TextSize = NAME_SIZE,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local desc = Components.label({
			Name = "Desc",
			Text = "",
			Size = UDim2.new(1, -CARD_SIDE, 0, DESC_H),
			Position = UDim2.fromOffset(8, DESC_Y),
			TextSize = DESC_SIZE,
			Color = COLORS.Muted,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		-- Long names ("Medium Coin Pouch") and the three-line descriptions shrink to fit their card instead of being
		-- cut off: scaled text, capped at the design sizes.
		for _, pair in { { name, NAME_SIZE }, { desc, DESC_SIZE } } do
			local label = pair[1] :: TextLabel
			label.TextScaled = true
			local constraint = Instance.new("UITextSizeConstraint")
			constraint.MaxTextSize = pair[2] :: number
			constraint.MinTextSize = 8
			constraint.Parent = label
		end

		-- Purchases go only through ctx.Purchase: it owns the prompt and the live price cache.
		local kind = item.Kind
		local key = item.Key
		local button = Components.button({
			Name = "Buy",
			Text = "",
			Size = UDim2.new(1, -BUTTON_SIDE, 0, BUTTON_H),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM),
			Color = COLORS.Good,
			TextSize = BUTTON_SIZE,
			OnClick = function()
				if kind == "Pass" then
					ctx.Purchase:PromptPass(key)
				else
					ctx.Purchase:PromptProduct(key)
				end
			end,
			Parent = frame,
		})

		frame.Parent = parent
		return { Item = item, Frame = frame, Name = name, Desc = desc, Button = button }
	end

	local sections: { Section } = {}

	for index, info in SECTIONS do
		local header = Components.label({
			Name = "Header_" .. tostring(index),
			Text = Strings.get(info.HeaderKey),
			Size = UDim2.new(1, 0, 0, HEADER_H),
			TextSize = HEADER_SIZE,
			Color = COLORS.Gold,
			XAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2 * index - 1,
			Parent = list,
		})

		-- The row is zero pixels tall in the list: AutomaticSize grows it to its grid.
		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(index)
		row.LayoutOrder = 2 * index
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
		grid.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
		grid.Parent = row

		row.Parent = list

		local cards: { Card } = {}
		for order, item in info.Items do
			table.insert(cards, buildCard(item, order, row))
		end
		table.insert(sections, { Header = header, Cards = cards })
	end

	-- Rewrites every card from a snapshot; never rebuilds one and never closes the panel.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local tier = num(state.HighestUnlockedTier, 1)
		local now = ctx.Now()

		for _, section in sections do
			local shown = 0

			for _, card in section.Cards do
				local item = card.Item
				local visible = isVisible(item, state, now)
				card.Frame.Visible = visible
				if visible then
					shown += 1
				end

				card.Desc.Text = describe(item, tier)

				-- A pass the player owns turns into a disabled badge; everything else shows its price.
				if item.Kind == "Pass" and ctx.Purchase:OwnsPass(item.Key) then
					card.Button.Text = Strings.get("Store.Owned")
					Components.setEnabled(card.Button, false)
				else
					card.Button.Text = ctx.Purchase:PriceText(item.Kind, item.Key)
					Components.setEnabled(card.Button, true)
				end
			end

			section.Header.Visible = shown > 0
		end
	end

	local screen: Screen = {
		Root = root,
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

	-- Prices, the policy flag and owned passes all arrive after the panel is built: repaint when they do.
	ctx.Purchase.Changed:Connect(function()
		refresh(ctx.State:Get())
	end)

	-- Nothing is known yet: every sellable card shows with the loading price until the first snapshot.
	refresh(nil)

	return screen
end

return Store
