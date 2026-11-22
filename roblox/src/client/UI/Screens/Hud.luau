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
local MUSIC_TAP_HOLD = 1.5 -- after a tap, the icon and label ignore the snapshot for this long
local LOOP_SECONDS = 1
local FALLBACK_SURGE_MINUTES = 5 -- only reached if Config.Economy is missing SurgeMinutes

export type Screen = {
	Root: Frame,
	Buttons: { [string]: TextButton },
	BrightnessSlot: Frame,
	MonetizationSlot: Frame,
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

	-- An increase ticks up over COIN_TWEEN_SECONDS; a decrease (or a repeated value) shows at once.
	local function setCoins(value: number)
		if coinTween then
			coinTween:Cancel()
			coinTween = nil
		end
		if value > coinValue.Value then
			coinTween = TweenService:Create(coinValue, TweenInfo.new(COIN_TWEEN_SECONDS), { Value = value })
			coinTween:Play()
		else
			coinValue.Value = value
		end
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

	-- 6. Bottom right: reserved space for the monetization entry points (batch 5).
	local monetizationSlot = Instance.new("Frame")
	monetizationSlot.Name = "MonetizationSlot"
	monetizationSlot.AnchorPoint = Vector2.new(1, 1)
	monetizationSlot.Position = UDim2.new(1, -104, 1, -EDGE)
	monetizationSlot.Size = UDim2.fromOffset(100, 64)
	monetizationSlot.BackgroundTransparency = 1
	monetizationSlot.Active = false
	monetizationSlot.Parent = root

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

	-- The newest snapshot, kept for the once-a-second refresh.
	local latest: any = nil

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
	end

	local screen: Screen = {
		Root = root,
		Buttons = buttons,
		BrightnessSlot = brightnessSlot,
		MonetizationSlot = monetizationSlot,
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
