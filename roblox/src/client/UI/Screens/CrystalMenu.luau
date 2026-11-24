--!strict
-- CrystalMenu.luau - the small panel that opens when the player taps one of their growing crystals. It shows
-- the seed's name and the time left, then up to three ways to skip the wait in one centred row: the paid
-- Instant Grow product, a rewarded video (with the ad disclosure) and a saved Instant Grow token. All three
-- are built once in new(); refresh only rewrites texts and Visible. Purchases and ads go through ctx.Purchase:
-- this screen never touches a remote, a price number or MarketplaceService.

-- Pixel layout inside the content frame.
local TIME_H = 26
local ROW_Y = 36
local ROW_H = 58
local ROW_PAD = 8 -- gap between two buttons of the row
local BUTTON_W = 136
local BUTTON_H = 56
local BUTTON_TEXT = 16
local FINISH_MIN_SECONDS = 10 -- batch 6: no paid or ad finish in the last seconds (the crystal could ripen during the prompt)

-- How often the countdown is repainted while the panel is open, in seconds.
local TICK_SECONDS = 0.5

-- Stand-ins for a snapshot that carries no ads or tokens yet (a fresh join).
local EMPTY_AD_COUNTS = { Date = "", FinishNow = 0, Luck = 0, CoinPouch = 0 }
local EMPTY_TOKENS = { S = 0, M = 0, L = 0 }

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

local CrystalMenu = {}

-- Builds the crystal menu inside ctx.Gui and returns the standard screen table.
function CrystalMenu.new(ctx: any): Screen
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

	-- The title starts empty: refresh writes the name of the seed that is growing.
	local root, content = Components.panel({
		Title = "",
		Size = UDim2.fromScale(0.66, 0.64),
		Name = "CrystalMenu",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("CrystalMenu")
		end,
	})

	-- The panel's own title label, reused for the seed name (nil would only mean a changed panel layout).
	local titleLabel: TextLabel? = nil
	local titleObject = root:FindFirstChild("Title")
	if titleObject ~= nil and titleObject:IsA("TextLabel") then
		titleLabel = titleObject
	end

	-- 1. The countdown line, rewritten on every tick.
	local timeLabel = Components.label({
		Name = "TimeLeft",
		Text = "",
		Size = UDim2.new(1, 0, 0, TIME_H),
		Position = UDim2.fromOffset(0, 0),
		TextSize = 20,
		Color = COLORS.Text,
		Parent = content,
	})

	-- 2. One centred row holds the ways out of the wait, in rule order: paid, free, token.
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Position = UDim2.new(0, 0, 0, ROW_Y)
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, ROW_PAD)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row

	row.Parent = content

	-- The pedestal on screen (nil when closed), whether a rewarded video is available, and the tick token.
	local index: number? = nil
	local adAvailable = false
	local tickToken = 0

	-- 3. Finish now: the paid Instant Grow product. The price comes live from ctx.Purchase and the server
	-- picks the real tier, so the client only shows what it is told.
	local finishNow = Components.button({
		Name = "FinishNow",
		Text = "",
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		Color = COLORS.Good,
		TextColor = COLORS.Bg,
		TextSize = BUTTON_TEXT,
		LayoutOrder = 1,
		OnClick = function()
			local pedestal = index
			ctx.UI:Close("CrystalMenu")
			if pedestal == nil then
				return
			end
			task.spawn(function()
				ctx.Purchase:InstantGrow(pedestal)
			end)
		end,
		Parent = row,
	})
	finishNow.Visible = false

	-- 4. Finish free: a rewarded video. The two-line text is the required ad disclosure (icon plus what
	-- watching it means), so the button turns RichText on once, here.
	local finishFree = Components.button({
		Name = "FinishFree",
		Text = "",
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		Color = COLORS.Gold,
		TextColor = COLORS.Bg,
		TextSize = BUTTON_TEXT,
		LayoutOrder = 2,
		OnClick = function()
			local pedestal = index
			ctx.UI:Close("CrystalMenu")
			if pedestal == nil then
				return
			end
			task.spawn(function()
				if not ctx.Purchase:RequestAd("FinishNow", pedestal) then
					ctx.UI:Toast(Strings.get("Toast.NoAd"))
				end
			end)
		end,
		Parent = row,
	})
	finishFree.RichText = true
	finishFree.Visible = false

	-- 5. Use token: spends a saved Instant Grow token of the tier this crystal needs (or a bigger one).
	local useToken = Components.button({
		Name = "UseToken",
		Text = "",
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		Color = COLORS.PanelLight,
		TextSize = BUTTON_TEXT,
		LayoutOrder = 3,
		OnClick = function()
			local pedestal = index
			if pedestal == nil then
				return
			end
			ctx.Purchase:UseToken(pedestal)
			ctx.UI:Close("CrystalMenu")
		end,
		Parent = row,
	})
	useToken.Visible = false

	-- Hides the panel and forgets the pedestal; bumping the token stops the tick loop at its next step.
	local function hide()
		root.Visible = false
		index = nil
		adAvailable = false
		tickToken += 1
	end

	-- Hides the panel and tells the router, so the backdrop and the one-panel-at-a-time lock follow along.
	local function closePanel()
		hide()
		ctx.UI:Close("CrystalMenu")
	end

	-- Repaints the whole panel from the snapshot; closes it once the crystal is gone or already ready.
	local function refresh()
		local snap = ctx.State:Get()

		if not root.Visible or index == nil then
			return
		end

		local pedestalIndex = index :: number
		local state = if isTable(snap) then snap else {}
		local pedestals = if isTable(state.Pedestals) then state.Pedestals else {}
		local crystal = pedestals[tostring(pedestalIndex)]

		if not isTable(crystal) then
			closePanel()
			return
		end

		local now = ctx.Now()
		local secondsLeft = num(crystal.ReadyAt, 0) - now

		if secondsLeft <= 0 then
			closePanel()
			return
		end
		local finishAllowed = secondsLeft > FINISH_MIN_SECONDS

		-- The title is the seed's name; the key depends on the seed, so it is built in a local first.
		local seedKey = "Seed." .. tostring(crystal.SeedId)
		local seedName = Strings.get(seedKey)
		if titleLabel ~= nil then
			titleLabel.Text = seedName
		end

		local countdown = ctx.Logic.Format.countdown(secondsLeft)
		timeLabel.Text = Strings.get("CrystalMenu.TimeLeft", { time = countdown })

		local monetization = if isTable(state.Monetization) then state.Monetization else {}
		local adCounts = if isTable(monetization.AdCounts) then monetization.AdCounts else EMPTY_AD_COUNTS
		local tokens = if isTable(monetization.InstantGrowTokens) then monetization.InstantGrowTokens else EMPTY_TOKENS

		-- Which product tier this wait maps to; the client only ever displays its live price.
		local key = ctx.Purchase:InstantGrowKey(secondsLeft)

		finishNow.Visible = finishAllowed and not ctx.Purchase:IsHidden("Product", key)
		finishNow.Text = Strings.get("CrystalMenu.FinishNow") .. "  " .. ctx.Purchase:PriceText("Product", key)

		-- The rewarded video shows only for a short crystal, only while one is available, and only while
		-- the player's daily caps have room (a cooldown still shows it: the server answers with its own toast).
		local finishFreeVisible = false
		if
			key == "InstantGrowS"
			and adAvailable
			and finishAllowed
			and not ctx.Purchase:IsHidden("Product", "InstantGrowS")
		then
			local adSettings = ctx.Config.Monetization
			local ads = if isTable(adSettings) then adSettings.Ads else nil
			if isTable(ads) then
				local today = ctx.Logic.WeekId.dateString(now)
				local lastAdAt = num(monetization.LastAdAt, 0)
				local ok, reason = ctx.Logic.AdCaps.check(adCounts, today, "FinishNow", now, lastAdAt, ads)
				finishFreeVisible = ok or reason == "Cooldown"
			end
		end

		finishFree.Visible = finishFreeVisible
		finishFree.Text = Theme.Icons.Ad
			.. " "
			.. Strings.get("CrystalMenu.FinishFree")
			.. '\n<font size="11">'
			.. Strings.get("Ad.Subtitle")
			.. "</font>"

		-- The token button: the smallest owned token that covers this crystal, nil when none does.
		local needed = string.sub(key, -1)
		local tier = ctx.Logic.InstantGrow.pickToken(tokens, needed)

		useToken.Visible = tier ~= nil
		if tier ~= nil then
			useToken.Text = Strings.get("CrystalMenu.UseToken", { tier = tier })
		end
	end

	-- Starts the countdown loop and returns the token that keeps it (and the ad probe) valid.
	local function startTick(): number
		tickToken += 1
		local myToken = tickToken
		task.spawn(function()
			while tickToken == myToken do
				task.wait(TICK_SECONDS)
				if tickToken ~= myToken then
					return
				end
				refresh()
			end
		end)
		return myToken
	end

	-- Yields: asks the ad service once per open whether a rewarded video can be shown right now.
	local function probeAd(openToken: number, openedIndex: number)
		task.spawn(function()
			local available = ctx.Purchase:CheckAd()
			if tickToken ~= openToken or index ~= openedIndex or not root.Visible then
				return
			end
			adAvailable = available
			refresh()
		end)
	end

	local screen: Screen = {
		Root = root,
		Open = function(args: any?)
			if typeof(args) ~= "number" then
				return
			end
			local openedIndex = args :: number
			index = openedIndex
			adAvailable = false
			root.Visible = true
			refresh()
			if not root.Visible then
				return -- refresh closed it: the crystal was gone or already ready
			end

			-- The countdown ticks on its own, and the ad button appears only once CheckAd has answered.
			local openToken = startTick()
			probeAd(openToken, openedIndex)
		end,
		Close = function()
			hide()
		end,
		Update = function(_snapshot: any)
			refresh()
		end,
		IsOpen = function(): boolean
			return root.Visible
		end,
	}

	-- Live prices and the paid-random-items flag arrive after the panel is built: repaint when they do.
	ctx.Purchase.Changed:Connect(function()
		refresh()
	end)

	return screen
end

return CrystalMenu
