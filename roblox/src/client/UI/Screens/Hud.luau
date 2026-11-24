--!strict
-- Hud.luau - the always-visible heads-up display: the two corner button grids, the coin counter, the
-- weekly-best pill, the music and brightness controls, the Shatter All button and the placeholder slots
-- later batches fill. The HUD is never closed, so Open/Close do nothing and IsOpen is always true.

local TweenService = game:GetService("TweenService")

-- Pixel layout. The safe area is about 685 x 280 px on a phone in landscape.
local EDGE = 8 -- distance from the safe-area border
local GAP = 4 -- gap between neighbouring buttons
local BUTTON_W = 108
local BUTTON_TEXT = 18 -- one text size for every grid button, so short labels don't look bigger
local BUTTON_H = 48
local COIN_PILL_W = 170
local COIN_PILL_H = 40
local WEEKLY_PILL_W = 110
local SHATTER_W = 180
local SHATTER_H = 52
local DOT_SIZE = 14
local COIN_TWEEN_SECONDS = 0.4 -- time the coin counter takes to tick up to a bigger value
local COIN_RELEASE_SECONDS = 0.15 -- short tick for one flying coin landing
local COIN_HOLD_SECONDS = 1.5 -- a hold releases itself when no coin arrives for this long
local COIN_HOLD_SAFETY_SECONDS = 1.6 -- the delayed check that guarantees the counter never stays stuck
local COIN_POP_SCALE = 1.12 -- the coin pill's small "pop" when a coin lands
local COIN_POP_SECONDS = 0.06 -- each half of that pop
local MUSIC_TAP_HOLD = 1.5 -- after a tap, the icon and label ignore the snapshot for this long
local LOOP_SECONDS = 1
local FALLBACK_SURGE_MINUTES = 5 -- only reached if Config.Economy is missing SurgeMinutes
local LUCK_AD_RECHECK_SECONDS = 30 -- how often the HUD re-asks the ad service about the free-luck ad
local LUCK_AD_MAX_LEFT = 300 -- the free-luck ad is only offered in the last five minutes of a boost

export type Screen = {
	Root: Frame,
	Buttons: { [string]: TextButton },
	BrightnessSlot: Frame,
	MonetizationSlot: Frame,
	-- The coin pill, so the EffectsController can fly coins into it, plus the two halves of that flight.
	CoinTarget: Frame,
	HoldCoins: (amount: number) -> (),
	ReleaseCoins: (amount: number) -> (),
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

local Hud = {}

-- Builds the HUD inside ctx.Gui and returns the standard screen table plus Buttons and BrightnessSlot.
function Hud.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local Format = ctx.Logic.Format
	local COLORS = Theme.Colors

	-- Guards every snapshot read: the server may send partial state while a profile is loading.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	-- Reads a number field, falling back for nil or wrongly typed values.
	local function num(value: any, fallback: number): number
		if typeof(value) == "number" then
			return value
		end
		return fallback
	end

	local root = Instance.new("Frame")
	root.Name = "Hud"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false -- taps pass through the HUD to the cave behind it
	root.Visible = true

	local buttons: { [string]: TextButton } = {}

	-- The newest snapshot, kept for the once-a-second refresh. Declared up here because the buttons built
	-- below (Auto, and the monetization refresh) read it from their handlers.
	local latest: any = nil

	-- Set later, once the music button exists; the button's OnClick only forwards to it.
	local musicTap: () -> () = function() end

	-- Builds one navigation button that opens a panel, and files it in `buttons`.
	local function navButton(
		name: string,
		icon: string,
		text: string,
		position: UDim2,
		anchorPoint: Vector2,
		panelName: string
	): TextButton
		local button = Components.button({
			Name = name,
			Icon = icon,
			Text = text,
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
			TextSize = BUTTON_TEXT,
			Position = position,
			AnchorPoint = anchorPoint,
			OnClick = function()
				ctx.UI:Open(panelName)
			end,
			Parent = root,
		})
		buttons[name] = button
		return button
	end

	-- Adds the 14x14 red notification dot to a button's top-right corner and returns it.
	local function addDot(button: TextButton): Frame
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(1, -2, 0, 2)
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = Theme.color(COLORS.Bad)
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.ZIndex = 5

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot

		dot.Parent = button
		return dot
	end

	-- Teleports the local character to the spawn point of the plot this player owns. Silent when the
	-- character, the map or the plot is not there yet.
	local function goToMyCave()
		local character = ctx.Player.Character
		if character == nil or not character:IsA("Model") then
			return
		end
		local map = workspace:FindFirstChild("Map")
		if map == nil then
			return
		end
		local plots = map:FindFirstChild("Plots")
		if plots == nil then
			return
		end
		local userId = tostring(ctx.Player.UserId)
		for _, plot in plots:GetChildren() do
			local owner = plot:GetAttribute("OwnerUserId")
			if owner ~= nil and tostring(owner) == userId then
				local spawnPoint = plot:FindFirstChild("SpawnPoint")
				if spawnPoint and spawnPoint:IsA("BasePart") then
					character:PivotTo(spawnPoint.CFrame + Vector3.new(0, 3, 0))
				end
				return
			end
		end
	end

	-- 1. Top-left 2x2 grid: cave, shop, upgrades, codex.
	buttons.MyCave = Components.button({
		Name = "MyCave",
		Icon = Theme.Icons.MyCave,
		Text = Strings.get("Hud.MyCave"),
		Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
		TextSize = BUTTON_TEXT,
		Position = UDim2.fromOffset(EDGE, EDGE),
		AnchorPoint = Vector2.new(0, 0),
		OnClick = goToMyCave,
		Parent = root,
	})
	navButton(
		"Shop",
		Theme.Icons.Shop,
		Strings.get("Hud.Shop"),
		UDim2.fromOffset(EDGE + BUTTON_W + GAP, EDGE),
		Vector2.new(0, 0),
		"Shop"
	)
	navButton(
		"Upgrades",
		Theme.Icons.Upgrades,
		Strings.get("Hud.Upgrades"),
		UDim2.fromOffset(EDGE, EDGE + BUTTON_H + GAP),
		Vector2.new(0, 0),
		"Upgrades"
	)
	navButton(
		"Codex",
		Theme.Icons.Codex,
		Strings.get("Hud.Codex"),
		UDim2.fromOffset(EDGE + BUTTON_W + GAP, EDGE + BUTTON_H + GAP),
		Vector2.new(0, 0),
		"Codex"
	)

	-- 2. Top centre: the coin pill with the animated counter, then the friend-bonus line under it.
	local coinPill = Instance.new("Frame")
	coinPill.Name = "Coins"
	coinPill.AnchorPoint = Vector2.new(0.5, 0)
	coinPill.Position = UDim2.new(0.5, 0, 0, EDGE)
	coinPill.Size = UDim2.fromOffset(COIN_PILL_W, COIN_PILL_H)
	coinPill.BackgroundColor3 = Theme.color(COLORS.Panel)
	coinPill.BorderSizePixel = 0

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(0, Theme.Corner)
	coinCorner.Parent = coinPill

	local coinLabel = Components.label({
		Name = "Amount",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextSize = 20,
		Color = COLORS.Gold,
		Parent = coinPill,
	})
	coinPill.Parent = root

	-- The displayed value lives on a NumberValue so a tween can tick it up frame by frame.
	local coinValue = Instance.new("NumberValue")
	coinValue.Name = "CoinValue"
	coinValue.Parent = root

	local function writeCoins(value: number)
		coinLabel.Text = Theme.Icons.Coins .. " " .. Strings.get("Hud.Coins", { coins = Format.compact(value) })
	end

	coinValue.Changed:Connect(function(value: number)
		writeCoins(value)
	end)
	writeCoins(0)

	local coinTween: Tween? = nil

	-- The latest snapshot's coin total.
	local serverCoins = 0
	-- Coins whose icons are still flying: they are held back so the counter can tick up as they arrive.
	local held = 0
	-- What the counter showed when the first icon left; the target never drops below it during a hold.
	local heldFloor: number? = nil
	-- After this clock time a hold releases itself, so a lost icon can never freeze the counter.
	local heldUntil = 0
	-- The pill's pop scale, created the first time a coin lands.
	local coinPop: UIScale? = nil

	-- The value the counter should be heading for: the snapshot minus whatever is still in flight.
	local function coinTarget(): number
		if held > 0 then
			return math.max(heldFloor or 0, serverCoins - held)
		end
		return serverCoins
	end

	-- An increase ticks up over `seconds`; a decrease (or a repeated value) shows at once.
	local function tweenTo(value: number, seconds: number)
		if coinTween then
			coinTween:Cancel()
			coinTween = nil
		end
		if value > coinValue.Value then
			coinTween = TweenService:Create(coinValue, TweenInfo.new(seconds), { Value = value })
			coinTween:Play()
		else
			coinValue.Value = value
		end
	end

	local function setCoins(value: number)
		serverCoins = value
		tweenTo(coinTarget(), COIN_TWEEN_SECONDS)
	end

	-- The pill's UIScale, created once and reused by every pop.
	local function coinPopScale(): UIScale
		local existing = coinPop
		if existing ~= nil then
			return existing
		end
		local created = Instance.new("UIScale")
		created.Name = "CoinPop"
		created.Parent = coinPill
		coinPop = created
		return created
	end

	-- Small pop on the pill (1 -> 1.12 -> 1) as a flying coin lands.
	local function popCoins()
		local scale = coinPopScale()
		scale.Scale = 1
		local up = TweenService:Create(scale, TweenInfo.new(COIN_POP_SECONDS), { Scale = COIN_POP_SCALE })
		up.Completed:Once(function()
			TweenService:Create(scale, TweenInfo.new(COIN_POP_SECONDS), { Scale = 1 }):Play()
		end)
		up:Play()
	end

	-- Holds `amount` coins back: the counter waits for the icons that are now flying towards it.
	local function HoldCoins(amount: number)
		local count = math.floor(amount)
		if count <= 0 then
			return
		end
		if held == 0 then
			heldFloor = coinValue.Value
		end
		held += count
		heldUntil = os.clock() + COIN_HOLD_SECONDS
		tweenTo(coinTarget(), COIN_TWEEN_SECONDS)

		task.delay(COIN_HOLD_SAFETY_SECONDS, function()
			-- Safety net: if no icon reported in, release everything, so the counter can never stay stuck.
			if held > 0 and os.clock() >= heldUntil then
				held = 0
				heldFloor = nil
				tweenTo(coinTarget(), COIN_TWEEN_SECONDS)
			end
		end)
	end

	-- Releases the share of one landed icon, ticks the counter a notch closer and pops the pill.
	local function ReleaseCoins(amount: number)
		held = math.max(0, held - math.floor(amount))
		if held == 0 then
			heldFloor = nil
		end
		tweenTo(coinTarget(), COIN_RELEASE_SECONDS)
		popCoins()
	end

	local friendLabel = Components.label({
		Name = "FriendBonus",
		Text = "",
		Size = UDim2.fromOffset(COIN_PILL_W, 22),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, EDGE + COIN_PILL_H + GAP),
		TextSize = 16,
		Color = COLORS.Good,
		Parent = root,
	})
	friendLabel.Visible = false

	-- Shows "Friends +N%" while the server publishes a positive FriendBonus attribute.
	local function refreshFriendBonus()
		local bonus = ctx.Player:GetAttribute("FriendBonus")
		if typeof(bonus) == "number" and bonus > 0 then
			local percent = math.floor(bonus * 100 + 0.5)
			friendLabel.Text = Strings.get("Hud.FriendBonus", { percent = percent })
			friendLabel.Visible = true
		else
			friendLabel.Visible = false
		end
	end
	ctx.Player:GetAttributeChangedSignal("FriendBonus"):Connect(refreshFriendBonus)

	-- 3. Top-right cluster, right to left: brightness slot, music button, weekly-best pill.
	local brightnessSlot = Instance.new("Frame")
	brightnessSlot.Name = "BrightnessSlot"
	brightnessSlot.AnchorPoint = Vector2.new(1, 0)
	brightnessSlot.Position = UDim2.new(1, -EDGE, 0, EDGE)
	brightnessSlot.Size = UDim2.fromOffset(48, 48)
	brightnessSlot.BackgroundTransparency = 1
	brightnessSlot.Active = false
	brightnessSlot.Parent = root

	local musicButton = Components.button({
		Name = "Music",
		Icon = Theme.Icons.MusicOn,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(EDGE + 48 + GAP), 0, EDGE),
		OnClick = function()
			musicTap()
		end,
		Parent = root,
	})

	local musicOn = true
	local musicHoldUntil = 0
	local musicLabelToken = 0

	local musicLabel = Components.label({
		Name = "MusicLabel",
		Text = "",
		Size = UDim2.fromOffset(WEEKLY_PILL_W + 6, 22),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(EDGE + 48 + GAP), 0, EDGE + 48 + GAP),
		TextSize = 16,
		Parent = root,
	})
	musicLabel.BackgroundColor3 = Theme.color(COLORS.Panel)
	musicLabel.BackgroundTransparency = 0.15
	musicLabel.ZIndex = 10
	musicLabel.Visible = false

	local musicLabelCorner = Instance.new("UICorner")
	musicLabelCorner.CornerRadius = UDim.new(0, Theme.Corner)
	musicLabelCorner.Parent = musicLabel

	-- Swaps the speaker glyph; `musicOn` doubles as the value the next tap flips.
	local function showMusicIcon(on: boolean)
		musicOn = on
		musicButton.Text = if on then Theme.Icons.MusicOn else Theme.Icons.MusicOff
	end

	-- Tap: flip at once, tell the sounds controller and the server, and flash a label for a moment.
	musicTap = function()
		local wanted = not musicOn
		showMusicIcon(wanted)
		ctx.Sounds:SetMusicFromTap(wanted)
		ctx.Remotes:WaitForChild("SetSetting"):FireServer("Music", wanted)

		musicHoldUntil = os.clock() + MUSIC_TAP_HOLD
		musicLabelToken += 1
		local token = musicLabelToken
		musicLabel.Text = if wanted then Strings.get("Hud.MusicOn") else Strings.get("Hud.MusicOff")
		musicLabel.Visible = true
		task.delay(MUSIC_TAP_HOLD, function()
			-- Only the newest tap hides the label.
			if token == musicLabelToken then
				musicLabel.Visible = false
			end
		end)
	end

	local weeklyPill = Instance.new("Frame")
	weeklyPill.Name = "WeeklyBest"
	weeklyPill.AnchorPoint = Vector2.new(1, 0)
	weeklyPill.Position = UDim2.new(1, -(EDGE + 48 + GAP + 48 + GAP), 0, EDGE)
	weeklyPill.Size = UDim2.fromOffset(WEEKLY_PILL_W, BUTTON_H)
	weeklyPill.BackgroundColor3 = Theme.color(COLORS.Panel)
	weeklyPill.BorderSizePixel = 0

	local weeklyCorner = Instance.new("UICorner")
	weeklyCorner.CornerRadius = UDim.new(0, Theme.Corner)
	weeklyCorner.Parent = weeklyPill

	local weeklyLabel = Components.label({
		Name = "Amount",
		Text = "",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextSize = 16,
		Color = COLORS.Gold,
		Parent = weeklyPill,
	})
	weeklyPill.Parent = root

	-- 4. Right 2x2 grid: daily, goals (both with a dot), surge (countdown) and odds.
	local rightColumnX = -(EDGE + BUTTON_W + GAP)
	local rightEdgeX = -EDGE
	local gridTop = EDGE + BUTTON_H + GAP

	navButton(
		"Daily",
		Theme.Icons.Daily,
		Strings.get("Hud.Daily"),
		UDim2.new(1, rightColumnX, 0, gridTop),
		Vector2.new(1, 0),
		"Daily"
	)
	local goalsButton = navButton(
		"Goals",
		Theme.Icons.Goals,
		Strings.get("Hud.Goals"),
		UDim2.new(1, rightEdgeX, 0, gridTop),
		Vector2.new(1, 0),
		"Goals"
	)
	local surgeButton = navButton(
		"Surge",
		Theme.Icons.Surge,
		"",
		UDim2.new(1, rightColumnX, 0, gridTop + BUTTON_H + GAP),
		Vector2.new(1, 0),
		"Odds"
	)
	navButton(
		"Odds",
		Theme.Icons.Odds,
		Strings.get("Hud.Odds"),
		UDim2.new(1, rightEdgeX, 0, gridTop + BUTTON_H + GAP),
		Vector2.new(1, 0),
		"Odds"
	)

	local dailyDot = addDot(buttons.Daily)
	local goalsDot = addDot(goalsButton)

	-- 5. Bottom centre: Shatter All, only while at least two crystals are ripe.
	local shatterButton = Components.button({
		Name = "ShatterAll",
		Text = Strings.get("Hud.ShatterAll", { count = 0 }),
		Size = UDim2.fromOffset(SHATTER_W, SHATTER_H),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -EDGE),
		Color = COLORS.Gold,
		TextColor = COLORS.Bg,
		OnClick = function()
			ctx.Remotes:WaitForChild("ShatterAll"):FireServer()
		end,
		Parent = root,
	})
	shatterButton.Visible = false
	buttons.ShatterAll = shatterButton

	-- Batch 5 monetization state: which way the luck button acts, and the cached free-luck ad probe.
	local luckMode = "Hidden" -- "Hidden" | "Active" | "Ad" | "Buy"
	local luckAdAvailable = false
	local luckAdCheckAt = 0
	local luckAdChecking = false
	local refreshMonetization: (snapshot: any) -> ()
	-- batch 6: the saved Auto Shatter setting as last seen, so a change can toast once.
	local lastAutoOn: boolean? = nil

	-- What a tap on the luck button does in its current mode.
	local function onLuckClick()
		if luckMode == "Active" then
			ctx.UI:Open("Odds") -- shows the boosted odds
		elseif luckMode == "Ad" then
			task.spawn(function()
				if not ctx.Purchase:RequestAd("Luck") then
					ctx.UI:Toast(Strings.get("Toast.NoAd"))
				end
				luckAdAvailable = false
				luckAdCheckAt = 0
			end)
		elseif luckMode == "Buy" then
			ctx.Purchase:PromptProduct("LuckBoost")
		end
	end

	-- 6. Bottom right, left of the jump button: the Store and Luck buttons (batch 5, change H), a hint label above
	-- them, and the Auto Shatter toggle left of Shatter All. All three buttons sit in `buttons`, so the tutorial
	-- lock disables them.
	local monetizationSlot = Instance.new("Frame")
	monetizationSlot.Name = "MonetizationSlot"
	monetizationSlot.AnchorPoint = Vector2.new(1, 1)
	monetizationSlot.Position = UDim2.new(1, -104, 1, -EDGE)
	monetizationSlot.Size = UDim2.fromOffset(128, 56)
	monetizationSlot.BackgroundTransparency = 1
	monetizationSlot.Active = false
	monetizationSlot.Parent = root

	local storeButton = Components.button({
		Name = "Store",
		Text = Theme.Icons.Store .. "\n" .. Strings.get("Hud.Store"),
		Size = UDim2.fromOffset(60, 56),
		Position = UDim2.fromOffset(0, 0),
		TextSize = 14,
		OnClick = function()
			ctx.UI:Open("Store")
		end,
		Parent = monetizationSlot,
	})
	buttons.Store = storeButton

	local luckButton = Components.button({
		Name = "Luck",
		Text = "",
		Size = UDim2.fromOffset(60, 56),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		TextSize = 14,
		OnClick = onLuckClick,
		Parent = monetizationSlot,
	})
	luckButton.Visible = false
	buttons.Luck = luckButton

	local luckHint = Components.label({
		Name = "LuckHint",
		Text = "",
		Size = UDim2.fromOffset(128, 18),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -104, 1, -EDGE - 56 - 2),
		Color = COLORS.Muted,
		XAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	luckHint.TextScaled = true
	local luckHintSize = Instance.new("UITextSizeConstraint")
	luckHintSize.MaxTextSize = 12
	luckHintSize.Parent = luckHint
	luckHint.Visible = false

	local autoButton = Components.button({
		Name = "Auto",
		Text = Theme.Icons.Auto .. "\n" .. Strings.get("Hud.AutoOff"),
		Size = UDim2.fromOffset(80, SHATTER_H),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -(SHATTER_W / 2) - 8, 1, -EDGE),
		TextSize = 16,
		OnClick = function()
			local on = isTable(latest) and isTable(latest.Settings) and latest.Settings.AutoShatter == true
			ctx.Remotes:WaitForChild("SetSetting"):FireServer("AutoShatter", not on)
		end,
		Parent = root,
	})
	autoButton.Visible = false
	buttons.Auto = autoButton

	-- Length of the surge window, straight from the config.
	local function surgeMinutes(): number
		local economy = ctx.Config.Economy
		if isTable(economy) then
			return num(economy.SurgeMinutes, FALLBACK_SURGE_MINUTES)
		end
		return FALLBACK_SURGE_MINUTES
	end

	-- Writes the surge countdown into its button, gold while the window is open.
	local function refreshSurge()
		local now = ctx.Now()
		local minutes = surgeMinutes()
		local active = ctx.Logic.Surge.isActive(now, minutes)
		local text: string
		if active then
			local remaining = (now - now % 3600) + minutes * 60 - now
			text = Strings.get("Hud.SurgeActive", { time = Format.countdown(remaining) })
		else
			text =
				Strings.get("Hud.SurgeIn", { time = Format.countdown(ctx.Logic.Surge.nextStart(now, minutes) - now) })
		end
		surgeButton.Text = Theme.Icons.Surge .. " " .. text
		surgeButton.TextColor3 = Theme.color(if active then COLORS.Gold else COLORS.Text)
	end

	-- How many planted crystals are ripe right now.
	local function readyCrystals(snapshot: any): number
		if not isTable(snapshot) or not isTable(snapshot.Pedestals) then
			return 0
		end
		local now = ctx.Now()
		local count = 0
		for _, crystal in snapshot.Pedestals do
			if
				isTable(crystal)
				and crystal.SeedId ~= nil
				and typeof(crystal.ReadyAt) == "number"
				and ctx.Logic.Growth.isReady(now, crystal.ReadyAt)
			then
				count += 1
			end
		end
		return count
	end

	-- Refreshes the Shatter All button and returns the count it shows.
	local function refreshShatterAll(snapshot: any): number
		local count = readyCrystals(snapshot)
		shatterButton.Text = Strings.get("Hud.ShatterAll", { count = count })
		shatterButton.Visible = count >= 2
		return count
	end

	-- Weekly best carats, only for the week that is running now.
	local function refreshWeeklyBest(snapshot: any)
		local best = if isTable(snapshot) then snapshot.WeeklyBest else nil
		local text = Strings.get("Hud.WeeklyBestEmpty")
		if
			isTable(best)
			and typeof(best.WeekId) == "string"
			and best.WeekId == ctx.Logic.WeekId.fromUnix(ctx.Now())
			and num(best.Carats, 0) > 0
		then
			text = Strings.get("Hud.WeeklyBest", { carats = Format.carats(num(best.Carats, 0)) })
		end
		weeklyLabel.Text = Theme.Icons.WeeklyBest .. " " .. text
	end

	-- True while any daily goal (or the all-goals bonus) is waiting to be claimed today.
	local function goalsClaimable(dailyGoals: any, today: string): boolean
		if not isTable(dailyGoals) or dailyGoals.Date ~= today or not isTable(dailyGoals.Goals) then
			return false
		end
		if ctx.Logic.Goals.canClaimBonus(dailyGoals) then
			return true
		end
		local progression = ctx.Config.Progression
		local pool = if isTable(progression) then progression.GoalPool else nil
		if not isTable(pool) then
			return false
		end
		for index = 1, #dailyGoals.Goals do
			if ctx.Logic.Goals.canClaim(dailyGoals, index, pool) then
				return true
			end
		end
		return false
	end

	-- Shows the red dots on Daily and Goals while there is something to claim.
	local function refreshDots(snapshot: any)
		if not isTable(snapshot) then
			dailyDot.Visible = false
			goalsDot.Visible = false
			return
		end
		-- batch 6: no red dots until the tutorial is done.
		if not (isTable(snapshot.Tutorial) and snapshot.Tutorial.Done == true) then
			dailyDot.Visible = false
			goalsDot.Visible = false
			return
		end
		local today = ctx.Logic.WeekId.dateString(ctx.Now())
		local streak = snapshot.Streak
		dailyDot.Visible = isTable(streak) and streak.LastClaimDate ~= today
		goalsDot.Visible = goalsClaimable(snapshot.DailyGoals, today)
	end

	-- Follows the server setting unless a tap happened less than MUSIC_TAP_HOLD ago.
	local function refreshMusic(snapshot: any)
		if os.clock() < musicHoldUntil then
			return
		end
		local settings = if isTable(snapshot) then snapshot.Settings else nil
		local on = true
		if isTable(settings) and typeof(settings.Music) == "boolean" then
			on = settings.Music
		end
		showMusicIcon(on)
	end

	-- Counts used while the snapshot has none yet: a fresh day with every ad still available.
	local EMPTY_AD_COUNTS = { Date = "", FinishNow = 0, Luck = 0, CoinPouch = 0 }

	-- Repaints the Store button, the luck button, the hint above them and the Auto Shatter toggle. Never yields:
	-- the one yielding call (the ad probe) runs in its own task and repaints again when it answers.
	refreshMonetization = function(snapshot: any)
		local now = ctx.Now()
		local state = if isTable(snapshot) then snapshot else {}
		local m = if isTable(state.Monetization) then state.Monetization else {}
		local endsAt = num(m.LuckBoostEndsAt, 0)

		storeButton.Visible = true
		autoButton.Visible = ctx.Purchase:OwnsPass("AutoShatter")
		local settings = state.Settings
		local autoOn = isTable(settings) and settings.AutoShatter == true
		autoButton.Text = Theme.Icons.Auto .. "\n" .. Strings.get(if autoOn then "Hud.AutoOn" else "Hud.AutoOff")
		local autoColor = if autoOn then COLORS.Good else COLORS.PanelLight
		-- While the tutorial lock has the button disabled, that grey is the colour to keep.
		if Components.isEnabled(autoButton) then
			autoButton.BackgroundColor3 = Theme.color(autoColor)
			autoButton:SetAttribute("NormalColor", autoColor)
		end

		-- batch 6: a real snapshot with the pass owned toasts when the saved setting changes; the first one only records it.
		if isTable(snapshot) and autoButton.Visible then
			if lastAutoOn ~= nil and autoOn ~= lastAutoOn then
				ctx.UI:Toast(Strings.get(if autoOn then "Toast.AutoOn" else "Toast.AutoOff"))
			end
			lastAutoOn = autoOn
		end

		if ctx.Purchase:IsHidden("Product", "LuckBoost") then
			luckMode = "Hidden"
			luckButton.Visible = false
			luckHint.Visible = false
			return
		end

		if endsAt > now then
			luckMode = "Active"
			luckButton.Text = Theme.Icons.Luck
				.. "\n"
				.. Strings.get("Hud.LuckActive", { time = Format.countdown(endsAt - now) })
			luckButton.TextColor3 = Theme.color(COLORS.Gold)
			luckButton.Visible = true
			luckHint.Visible = false
			return
		end

		-- No boost running: offer the free video once the caps allow it, otherwise the paid product.
		local canAd = ctx.Logic.LuckBoost.canWatchAd(now, endsAt, LUCK_AD_MAX_LEFT)
		local adCounts = if isTable(m.AdCounts) then m.AdCounts else EMPTY_AD_COUNTS
		local ok, reason = ctx.Logic.AdCaps.check(
			adCounts,
			ctx.Logic.WeekId.dateString(now),
			"Luck",
			now,
			num(m.LastAdAt, 0),
			ctx.Config.Monetization.Ads
		)
		local capsAllow = ok or reason == "Cooldown"

		if canAd and capsAllow and not ctx.Purchase:IsRestricted() then
			-- Re-probe the ad service every LUCK_AD_RECHECK_SECONDS; one answer covers a single ad.
			if not luckAdChecking and now - luckAdCheckAt >= LUCK_AD_RECHECK_SECONDS then
				luckAdChecking = true
				luckAdCheckAt = now
				task.spawn(function()
					luckAdAvailable = ctx.Purchase:CheckAd()
					luckAdChecking = false
					refreshMonetization(latest)
				end)
			end
		else
			luckAdAvailable = false
		end

		if luckAdAvailable and canAd and capsAllow then
			luckMode = "Ad"
			luckButton.Text = Theme.Icons.Ad .. "\n" .. Strings.get("Ad.FreeLuck")
			luckButton.TextColor3 = Theme.color(COLORS.Text)
			luckHint.Text = Strings.get("Ad.Subtitle")
			luckHint.Visible = true
		else
			luckMode = "Buy"
			luckButton.Text = Theme.Icons.Luck .. "\n" .. ctx.Purchase:PriceText("Product", "LuckBoost")
			luckButton.TextColor3 = Theme.color(COLORS.Text)
			-- The hint points at the free alternative: the next surge window, unless one is open right now.
			local minutes = surgeMinutes()
			if not ctx.Logic.Surge.isActive(now, minutes) then
				local nextStart = ctx.Logic.Surge.nextStart(now, minutes)
				luckHint.Text = Strings.get("Hud.NextFreeSurge", { time = Format.countdown(nextStart - now) })
				luckHint.Visible = true
			else
				luckHint.Visible = false
			end
		end
		luckButton.Visible = true
	end

	-- Prices, the policy flag and owned passes arrive after the HUD is built: repaint when they do.
	ctx.Purchase.Changed:Connect(function()
		refreshMonetization(latest)
	end)

	-- Refreshes every part of the HUD from a public-profile snapshot, in place.
	local function update(snapshot: any)
		if not isTable(snapshot) then
			return
		end
		latest = snapshot
		setCoins(math.max(0, num(snapshot.Coins, 0)))
		refreshWeeklyBest(snapshot)
		refreshDots(snapshot)
		refreshMusic(snapshot)
		refreshShatterAll(snapshot)
		refreshMonetization(snapshot)
	end

	local screen: Screen = {
		Root = root,
		Buttons = buttons,
		BrightnessSlot = brightnessSlot,
		MonetizationSlot = monetizationSlot,
		CoinTarget = coinPill,
		HoldCoins = HoldCoins,
		ReleaseCoins = ReleaseCoins,
		Open = function(_args: any?) end,
		Close = function() end,
		Update = update,
		IsOpen = function(): boolean
			return true
		end,
	}

	-- Everything is built, so attach the HUD last.
	root.Parent = ctx.Gui

	refreshFriendBonus()
	refreshSurge()
	refreshWeeklyBest(nil)
	refreshMusic(nil)
	refreshMonetization(nil)

	-- Once-a-second refresh: countdowns, ripening crystals, the ready sound and things that roll over
	-- (the UTC date and the ISO week) while the HUD sits open.
	task.spawn(function()
		local previousReady: number? = nil
		while root.Parent ~= nil do
			task.wait(LOOP_SECONDS)
			refreshSurge()
			local snapshot = latest
			if snapshot ~= nil then
				-- A crystal ripening while the HUD is open plays the "Ready" jingle; the first check stays silent.
				local ready = refreshShatterAll(snapshot)
				if previousReady ~= nil and ready > previousReady then
					ctx.Sounds:Play("Ready")
				end
				previousReady = ready
				refreshDots(snapshot)
				refreshWeeklyBest(snapshot)
			end
		end
	end)

	return screen
end

return Hud
