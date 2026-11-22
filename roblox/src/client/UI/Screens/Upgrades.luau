--!strict
-- Upgrades.luau - the upgrades panel: two side-by-side cards, one for display pedestals and one for the
-- growth lamp. Each card shows the current level, what the upgrade does and the price of the next one.
-- Both cards are built once in new(); Update only rewrites texts and colours in place.

-- Card layout, in pixels inside the content frame.
local CARD_GAP = 12 -- total gap between the two cards (6 px each side)
local TITLE_Y = 8
local TITLE_H = 26
local EFFECT_Y = 40
local EFFECT_H = 20
local BUTTON_H = 52
local BUTTON_BOTTOM = 10
local BUTTON_SIDE = 20 -- button width is 1 scale minus this

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One upgrade card: its title, effect line and buy button, all refreshed in place.
type Card = {
	Frame: Frame,
	Title: TextLabel,
	Effect: TextLabel,
	Button: TextButton,
}

local Upgrades = {}

-- Builds the upgrades panel inside ctx.Gui and returns the standard screen table.
function Upgrades.new(ctx: any): Screen
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

	local root, content = Components.panel({
		Title = Strings.get("Upgrades.Title"),
		Size = UDim2.fromScale(0.62, 0.72),
		Name = "Upgrades",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Upgrades")
		end,
	})

	-- Builds one card of the pair; xScale/xOffset place it in its half of the content frame.
	local function buildCard(
		name: string,
		layoutOrder: number,
		xScale: number,
		xOffset: number,
		onClick: () -> ()
	): Card
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.LayoutOrder = layoutOrder
		frame.Position = UDim2.new(xScale, xOffset, 0, 0)
		frame.Size = UDim2.new(0.5, -CARD_GAP / 2, 1, 0)
		frame.BackgroundColor3 = Theme.color(COLORS.PanelLight)
		frame.BorderSizePixel = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = Theme.color(COLORS.Stroke)
		stroke.Parent = frame

		local title = Components.label({
			Name = "Title",
			Text = "",
			Size = UDim2.new(1, -16, 0, TITLE_H),
			Position = UDim2.fromOffset(8, TITLE_Y),
			TextSize = 18,
			Color = COLORS.Gold,
			Parent = frame,
		})

		local effect = Components.label({
			Name = "Effect",
			Text = "",
			Size = UDim2.new(1, -16, 0, EFFECT_H),
			Position = UDim2.fromOffset(8, EFFECT_Y),
			TextSize = 15,
			Color = COLORS.Muted,
			Parent = frame,
		})

		local button = Components.button({
			Name = "Buy",
			Text = "",
			Size = UDim2.new(1, -BUTTON_SIDE, 0, BUTTON_H),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM),
			Color = COLORS.Good,
			TextColor = COLORS.Bg,
			TextSize = 20,
			OnClick = onClick,
			Parent = frame,
		})

		frame.Parent = content
		return { Frame = frame, Title = title, Effect = effect, Button = button }
	end

	local pedestalCard = buildCard("Pedestal", 1, 0, 0, function()
		ctx.Remotes:WaitForChild("BuyUpgrade"):FireServer("Pedestal")
	end)

	local lampCard = buildCard("Lamp", 2, 0.5, CARD_GAP / 2, function()
		ctx.Remotes:WaitForChild("BuyUpgrade"):FireServer("Lamp")
	end)

	-- Paints a buy button: green when affordable, muted when the player is short (still tappable so the
	-- server can answer with a toast), disabled and greyed once the ladder is finished.
	local function paintButton(button: TextButton, cost: number?, coins: number)
		button:SetAttribute("NormalColor", COLORS.Good)
		Components.setEnabled(button, true)
		if cost ~= nil and coins < cost then
			button.BackgroundColor3 = Theme.color(COLORS.PanelLight)
			button.TextColor3 = Theme.color(COLORS.Muted)
		else
			button.BackgroundColor3 = Theme.color(COLORS.Good)
			button.TextColor3 = Theme.color(COLORS.Bg)
		end
	end

	-- Rewrites both cards from a snapshot; never rebuilds and never closes the panel.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local coins = num(state.Coins, 0)
		local economy = ctx.Config.Economy
		local logicEconomy = ctx.Logic.Economy

		if not isTable(economy) then
			return
		end

		-- 1. Display pedestals: the level, the effect and the price of the next slot.
		local maxPedestals = num(economy.MaxCoinPedestals, 0)
		local pedestals = num(state.UnlockedPedestals, 0)
		local pedestalCosts = economy.PedestalCosts
		local pedestalCost: number? = if isTable(pedestalCosts)
			then logicEconomy.nextPedestalCost(pedestals, pedestalCosts, maxPedestals)
			else nil

		pedestalCard.Title.Text = Strings.get("Upgrades.Pedestal", { level = pedestals, max = maxPedestals })
		pedestalCard.Effect.Text = Strings.get("Upgrades.PedestalEffect")

		local pedestalButton = pedestalCard.Button
		if pedestalCost == nil then
			pedestalButton.Text = Strings.get("Upgrades.Max")
			Components.setEnabled(pedestalButton, false)
		else
			pedestalButton.Text = Theme.Icons.Coins .. " " .. ctx.Logic.Format.compact(pedestalCost)
			paintButton(pedestalButton, pedestalCost, coins)
		end

		-- 2. Growth lamp: the level, the current reduction and the price of the next lamp.
		local lampCosts = economy.LampCosts
		local lampLevel = num(state.LampLevel, 0)
		local lampMax = if isTable(lampCosts) then #lampCosts else 0
		local lampStep = num(economy.LampStep, 0)
		local lampCost: number? = if isTable(lampCosts) then logicEconomy.nextLampCost(lampLevel, lampCosts) else nil
		local percent = math.floor(lampLevel * lampStep * 100 + 0.5)

		lampCard.Title.Text = Strings.get("Upgrades.Lamp", { level = lampLevel, max = lampMax })
		lampCard.Effect.Text = Strings.get("Upgrades.LampEffect", { percent = percent })

		local lampButton = lampCard.Button
		if lampCost == nil then
			lampButton.Text = Strings.get("Upgrades.Max")
			Components.setEnabled(lampButton, false)
		else
			lampButton.Text = Theme.Icons.Coins .. " " .. ctx.Logic.Format.compact(lampCost)
			paintButton(lampButton, lampCost, coins)
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

	-- Sensible defaults until the first snapshot arrives: MAX until a level is known.
	refresh(nil)

	return screen
end

return Upgrades
