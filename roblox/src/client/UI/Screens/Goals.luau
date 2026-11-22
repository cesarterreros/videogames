--!strict
-- Goals.luau - the daily goals panel: three goal rows (title, progress bar, reward and a claim button)
-- plus the surprise-seed bonus row that unlocks once all three are claimed. All four rows are built
-- once in new(); Update only rewrites texts, colours and enabled state in place.

-- Row layout, in pixels inside the content frame.
local ROW_H = 54 -- height of every row
local ROW_GAP = 6 -- spacing between rows
local GOAL_COUNT = 3 -- goals drawn per day
local LABEL_Y = 2
local LABEL_H = 24
local LABEL_W = 0.42 -- title width, as a scale of the row
local BAR_Y = 28
local BAR_H = 18
local REWARD_X = 0.47 -- reward column starts at this scale of the row
local REWARD_W = 0.22
local BUTTON_W = 110
local BUTTON_H = 48
local BUTTON_X = -6 -- button inset from the right edge

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One goal row: its title, progress bar, reward label and claim button.
type GoalRow = {
	Frame: Frame,
	Title: TextLabel,
	Bar: { Root: Frame, Set: (fraction: number, text: string) -> () },
	Reward: TextLabel,
	Button: TextButton,
}

local Goals = {}

-- Builds the daily goals panel inside ctx.Gui and returns the standard screen table.
function Goals.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local Format = ctx.Logic.Format
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

	local progression = if isTable(ctx.Config.Progression) then ctx.Config.Progression else {}
	local pool: { any } = if isTable(progression.GoalPool) then progression.GoalPool else {}
	local seeds: { any } = if isTable(ctx.Config.Seeds) then ctx.Config.Seeds else {}
	local rewardMult = num(progression.GoalRewardValueMult, 1)

	local root, content = Components.panel({
		Title = Strings.get("Goals.Title"),
		Size = UDim2.fromScale(0.78, 0.9),
		Name = "Goals",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Goals")
		end,
	})

	-- The 4 rows are taller than a phone's panel, so they scroll instead of being clipped.
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Rows"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.ScrollBarThickness = 6
	scroller.Parent = content

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, ROW_GAP)
	list.Parent = scroller

	-- Builds one rounded row frame with its title label; callers add the rest of the content.
	local function buildRowFrame(name: string, layoutOrder: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.LayoutOrder = layoutOrder
		frame.Size = UDim2.new(1, -8, 0, ROW_H) -- room for the scrollbar
		frame.BackgroundColor3 = Theme.color(COLORS.PanelLight)
		frame.BorderSizePixel = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = frame

		frame.Parent = scroller
		return frame
	end

	-- A row's claim button, anchored to the right edge and vertically centred.
	local function buildClaimButton(row: Frame, onClick: () -> ()): TextButton
		return Components.button({
			Name = "Claim",
			Text = "",
			Size = UDim2.fromOffset(BUTTON_W, BUTTON_H),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, BUTTON_X, 0.5, 0),
			Color = COLORS.PanelLight,
			TextSize = 18,
			OnClick = onClick,
			Parent = row,
		})
	end

	-- Builds one goal row: title, progress bar, reward and claim button.
	local function buildGoalRow(index: number): GoalRow
		local frame = buildRowFrame("Goal" .. index, index)

		local title = Components.label({
			Name = "Title",
			Text = "",
			Size = UDim2.new(LABEL_W, -10, 0, LABEL_H),
			Position = UDim2.fromOffset(10, LABEL_Y),
			TextSize = 16,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		local bar = Components.progressBar({
			Name = "Progress",
			Size = UDim2.new(LABEL_W, -10, 0, BAR_H),
			Position = UDim2.fromOffset(10, BAR_Y),
			Parent = frame,
		})

		local reward = Components.label({
			Name = "Reward",
			Text = "",
			Size = UDim2.new(REWARD_W, 0, 1, 0),
			Position = UDim2.new(REWARD_X, 0, 0, 0),
			TextSize = 18,
			Color = COLORS.Gold,
			Parent = frame,
		})

		local button = buildClaimButton(frame, function()
			ctx.Remotes:WaitForChild("ClaimGoal"):FireServer(index)
		end)

		return { Frame = frame, Title = title, Bar = bar, Reward = reward, Button = button }
	end

	local rows: { GoalRow } = {}
	for index = 1, GOAL_COUNT do
		rows[index] = buildGoalRow(index)
	end

	-- The bonus row: the surprise seed name plus the "finish all 3 goals" hint.
	local bonusFrame = buildRowFrame("Bonus", GOAL_COUNT + 1)

	local bonusTitle = Components.label({
		Name = "Title",
		Text = Strings.get("Goals.Bonus"),
		Size = UDim2.new(LABEL_W, -10, 0, LABEL_H),
		Position = UDim2.fromOffset(10, LABEL_Y),
		TextSize = 16,
		Color = COLORS.Gold,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = bonusFrame,
	})

	local bonusHint = Components.label({
		Name = "Hint",
		Text = "",
		Size = UDim2.new(1, -BUTTON_W - 30, 0, BAR_H),
		Position = UDim2.fromOffset(10, BAR_Y),
		TextSize = 14,
		Color = COLORS.Muted,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = bonusFrame,
	})

	local bonusButton = buildClaimButton(bonusFrame, function()
		ctx.Remotes:WaitForChild("ClaimGoal"):FireServer("Bonus")
	end)

	-- Paints a claim button: green with dark text when it can be tapped, grey when it cannot.
	local function paintButton(button: TextButton, text: string, enabled: boolean)
		button.Text = text
		if enabled then
			button:SetAttribute("NormalColor", COLORS.Good)
			Components.setEnabled(button, true)
			button.TextColor3 = Theme.color(COLORS.Bg)
		else
			Components.setEnabled(button, false)
			button.TextColor3 = Theme.color(COLORS.Muted)
		end
	end

	-- Target of the pool entry behind a goal Id, or nil when the Id is unknown.
	local function targetFor(id: any): number?
		if typeof(id) ~= "string" then
			return nil
		end
		for _, entry in pool do
			if isTable(entry) and entry.Id == id and typeof(entry.Target) == "number" then
				return entry.Target
			end
		end
		return nil
	end

	-- Rewrites all four rows from a snapshot; never rebuilds and never closes the panel.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local daily = state.DailyGoals
		local dailyOk = isTable(daily) and isTable(daily.Goals)
		local goals: { any } = if dailyOk then daily.Goals else {}
		local today = ctx.Logic.WeekId.dateString(ctx.Now())
		-- Goals drawn for an earlier day stay visible, but nothing may be claimed until the server redraws.
		local stale = not isTable(daily) or daily.Date ~= today
		local tier = num(state.HighestUnlockedTier, 1)
		local rewardText = Strings.get("Goals.Reward", {
			coins = Format.compact(ctx.Logic.Economy.goalReward(seeds, tier, rewardMult)),
		})

		for index = 1, GOAL_COUNT do
			local row = rows[index]
			local goal = goals[index]
			local target = targetFor(if isTable(goal) then goal.Id else nil)

			if not isTable(goal) or target == nil then
				row.Frame.Visible = false
				continue
			end

			local needed = target :: number
			local goalKey = "Goal." .. goal.Id
			local progress = num(goal.Progress, 0)
			local capped = math.min(progress, needed)
			local denominator = if needed > 0 then needed else 1

			row.Frame.Visible = true
			row.Title.Text = Strings.get(goalKey)
			row.Reward.Text = rewardText
			row.Bar.Set(
				capped / denominator,
				Strings.get("Goals.Progress", {
					progress = Format.compact(capped),
					target = Format.compact(needed),
				})
			)

			if goal.Claimed == true then
				paintButton(row.Button, Strings.get("Goals.Claimed"), false)
			else
				local canClaim = dailyOk and not stale and ctx.Logic.Goals.canClaim(daily, index, pool) == true
				paintButton(row.Button, Strings.get("Goals.Claim"), canClaim)
			end
		end

		if not isTable(daily) then
			bonusFrame.Visible = false
			return
		end

		bonusFrame.Visible = true
		local seedId = ctx.Logic.Economy.surpriseSeedId(seeds, tier)
		local seedKey = "Seed." .. seedId
		bonusHint.Text = Strings.get(seedKey) .. " — " .. Strings.get("Goals.BonusHint")

		if daily.BonusClaimed == true then
			paintButton(bonusButton, Strings.get("Goals.Claimed"), false)
		else
			local canBonus = dailyOk and not stale and ctx.Logic.Goals.canClaimBonus(daily) == true
			paintButton(bonusButton, Strings.get("Goals.Claim"), canBonus)
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

	-- Sensible defaults until the first snapshot arrives: every row hidden but laid out.
	refresh(nil)

	return screen
end

return Goals
