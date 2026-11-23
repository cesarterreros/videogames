--!strict
-- OfferPopup.luau - the session's one popup offer: the Starter Pack or the Double Coins pass. Kid-safe by
-- design: a big close button, no countdown and no pressure text. UIController opens it once the screen is
-- clear (Open({ kind = "StarterPack" })), the offer and its price come from ctx.Purchase, and this screen
-- never touches a remote itself: buying goes only through the prompt helpers of ctx.Purchase.

-- Content layout, in pixels inside the content frame (the panel is 0.6 x 0.8 of a phone-sized safe area).
local DESC_H = 60
local DESC_SIZE = 18
local BUY_W = 220
local BUY_H = 56
local BUY_SIZE = 22

-- The two offers this popup knows how to show.
local KINDS: { [string]: boolean } = {
	StarterPack = true,
	DoubleCoins = true,
}

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

local OfferPopup = {}

-- Builds the offer popup inside ctx.Gui and returns the standard screen table.
function OfferPopup.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local COLORS = Theme.Colors

	-- The offer on show ("StarterPack" or "DoubleCoins"), nil while the popup is closed.
	local kind: string? = nil

	-- Guards every snapshot read: the server may send partial state while a profile is loading.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	-- Reads a number field, falling back when the config or the snapshot is missing it.
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

	-- The translated name of one seed; the key depends on the seed, so it is built here first.
	local function seedName(id: any): string
		local seedKey = "Seed." .. tostring(id)
		return Strings.get(seedKey)
	end

	local root, content = Components.panel({
		Title = "",
		Size = UDim2.fromScale(0.6, 0.8),
		Name = "OfferPopup",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("OfferPopup")
		end,
	})

	-- The X button is the main way out of this popup, so it is bigger than the panel default (it keeps its
	-- position and anchor point: only the touch target grows).
	local closeChild = root:FindFirstChild("Close")
	if closeChild ~= nil and closeChild:IsA("GuiObject") then
		local closeButton = closeChild :: GuiObject
		closeButton.Size = UDim2.fromOffset(56, 56)
	end

	-- The panel title carries the offer's name; the text is written on Open, when the kind is known.
	local titleChild = root:FindFirstChild("Title")
	local titleLabel: TextLabel? = if titleChild ~= nil and titleChild:IsA("TextLabel")
		then titleChild :: TextLabel
		else nil
	if titleLabel ~= nil then
		titleLabel.TextColor3 = Theme.color(COLORS.Gold)
	end

	-- What the offer contains (one wrapped paragraph) and the one way in: the Roblox purchase prompt.
	local desc = Components.label({
		Name = "Desc",
		Text = "",
		Size = UDim2.new(1, 0, 0, DESC_H),
		Position = UDim2.fromOffset(0, 0),
		TextSize = DESC_SIZE,
		Color = COLORS.Text,
		Parent = content,
	})

	local buy = Components.button({
		Name = "Buy",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(BUY_W, BUY_H),
		Color = COLORS.Good,
		TextColor = COLORS.Bg,
		TextSize = BUY_SIZE,
		OnClick = function()
			if kind == "StarterPack" then
				ctx.Purchase:PromptProduct("StarterPack")
			elseif kind == "DoubleCoins" then
				ctx.Purchase:PromptPass("DoubleCoins")
			end
			ctx.UI:Close("OfferPopup")
		end,
		Parent = content,
	})

	-- Rewrites the description and the buy label for the offer on show; no price is ever written here.
	local function refresh()
		local current = kind
		if current == nil then
			return
		end

		if current == "StarterPack" then
			local pack = product("StarterPack")
			desc.Text = Strings.get("Product.StarterPack.Desc", {
				coins = ctx.Logic.Format.compact(num(pack.Coins, 0)),
				count = num(pack.Count, 0),
				seed = seedName(pack.SeedId),
				minutes = num(pack.LuckMinutes, 0),
			})
			buy.Text = ctx.Purchase:PriceText("Product", "StarterPack")
			return
		end

		desc.Text = Strings.get("Pass.DoubleCoins.Desc")
		buy.Text = ctx.Purchase:PriceText("Pass", "DoubleCoins")
	end

	-- The offer's title key depends on the kind, so it is built in a local before the lookup.
	local function offerTitle(current: string): string
		local titleKey = "Offer." .. current .. ".Title"
		return Strings.get(titleKey)
	end

	-- True when this offer must not be shown at all: not sold here, restricted, already bought or owned.
	local function isSpent(current: string): boolean
		if current == "StarterPack" then
			if ctx.Purchase:IsHidden("Product", "StarterPack") then
				return true
			end
			local snapshot = ctx.State:Get()
			local monetization = if isTable(snapshot) then snapshot.Monetization else nil
			if not isTable(monetization) then
				return false
			end
			return monetization.StarterPackBought == true
		end
		return ctx.Purchase:IsHidden("Pass", "DoubleCoins") or ctx.Purchase:OwnsPass("DoubleCoins")
	end

	local screen: Screen = {
		Root = root,
		Open = function(args: any?)
			if not isTable(args) then
				return
			end
			local requested = args.kind
			if typeof(requested) ~= "string" or not KINDS[requested] then
				return
			end

			-- Nothing to offer any more: make sure the popup is not left on screen.
			if isSpent(requested) then
				ctx.UI:Close("OfferPopup")
				return
			end

			kind = requested

			local label = titleLabel
			if label ~= nil then
				label.Text = offerTitle(requested)
			end

			refresh()
			root.Visible = true
		end,
		Close = function()
			root.Visible = false
			kind = nil
		end,
		Update = function(_snapshot: any)
			refresh()
		end,
		IsOpen = function(): boolean
			return root.Visible
		end,
	}

	-- Prices and the policy flag arrive after the popup is built: repaint the offer when they do.
	ctx.Purchase.Changed:Connect(function()
		refresh()
	end)

	return screen
end

return OfferPopup
