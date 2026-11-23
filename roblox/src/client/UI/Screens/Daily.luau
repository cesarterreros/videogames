--!strict
-- Daily.luau - the 7-day login streak panel: one tile per streak day, the tile that pays out today
-- outlined in gold, and a single Claim button beneath the row. All tiles are built once in new();
-- Update only repaints them, so the panel never closes itself and never rebuilds its UI.

-- Tile row layout, in pixels inside the content frame.
local ROW_H = 90 -- height of the strip of day tiles (labels use 74 px; the whole panel must fit a 280 px phone)
local TILE_GAP = 6 -- spacing between tiles (also taken off each tile width)
local TILE_PAD = 8 -- inner padding of a tile's labels
local DAY_LABEL_Y = 8
local DAY_LABEL_H = 22
local REWARD_LABEL_Y = 34
local REWARD_LABEL_H = 40
local CLAIM_Y = 98
local CLAIM_W = 200
local CLAIM_H = 52
local HINT_Y = CLAIM_Y + CLAIM_H + 6
local HINT_H = 22
local HINT_W = 300
local AD_SHIFT = 108 -- each button's centre moves this far from the row centre when the ad button shows
local AD_W = 200
local AD_RECHECK_SECONDS = 30
local REFRESH_SECONDS = 1 -- the UTC date can roll over while the panel is open

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One streak tile: its frame, outline and the two labels that dim once the day is already claimed.
type Tile = {
	Frame: Frame,
	Stroke: UIStroke,
	Day: TextLabel,
	Reward: TextLabel,
}

local Daily = {}

-- Builds the daily reward panel inside ctx.Gui and returns the standard screen table.
function Daily.new(ctx: any): Screen
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
	local days: { any } = if isTable(progression.Streak) then progression.Streak else {}
	local dayCount = #days
	local tileWidth = 1 / math.max(dayCount, 1)

	local root, content = Components.panel({
		Title = Strings.get("Daily.Title"),
		Size = UDim2.fromScale(0.78, 0.9), -- tiles, Claim and the "come back" line fit a phone
		Name = "Daily",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Daily")
		end,
	})

	-- Text of a tile reward: coins show the coin icon, seeds their name plus a count.
	local function tileRewardText(entry: any): string
		if not isTable(entry) then
			return ""
		end
		if typeof(entry.Coins) == "number" then
			return Theme.Icons.Coins .. " " .. Format.compact(entry.Coins)
		end
		if typeof(entry.Seed) == "string" then
			local seedKey = "Seed." .. entry.Seed
			local count = num(entry.Count, 1)
			return Strings.get(seedKey) .. " " .. Strings.get("SeedPicker.Count", { count = count })
		end
		return ""
	end

	-- The strip of 7 tiles, laid out left to right and centred.
	local row = Instance.new("Frame")
	row.Name = "Days"
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.Position = UDim2.fromOffset(0, 0)
	row.BackgroundTransparency = 1

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, TILE_GAP)
	rowLayout.Parent = row

	local tiles: { Tile } = {}
	for index, entry in days do
		local tile = Instance.new("Frame")
		tile.Name = "Day" .. index
		tile.LayoutOrder = index
		tile.Size = UDim2.new(tileWidth, -TILE_GAP, 1, 0)
		tile.BackgroundColor3 = Theme.color(COLORS.PanelLight)
		tile.BorderSizePixel = 0

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = tile

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = Theme.color(COLORS.Stroke)
		stroke.Parent = tile

		local dayLabel = Components.label({
			Name = "Day",
			Text = Strings.get("Daily.Day", { day = index }),
			Size = UDim2.new(1, -TILE_PAD * 2, 0, DAY_LABEL_H),
			Position = UDim2.fromOffset(TILE_PAD, DAY_LABEL_Y),
			TextSize = 16,
			Color = COLORS.Gold,
			Parent = tile,
		})

		local rewardLabel = Components.label({
			Name = "Reward",
			Text = tileRewardText(entry),
			Size = UDim2.new(1, -TILE_PAD * 2, 0, REWARD_LABEL_H),
			Position = UDim2.fromOffset(TILE_PAD, REWARD_LABEL_Y),
			Color = COLORS.Text,
			Parent = tile,
		})
		-- Shrink to fit (capped at 15 px) so a long seed name never breaks mid-word in a narrow tile.
		local rewardSize = rewardLabel:FindFirstChildOfClass("UITextSizeConstraint")
		if rewardSize then
			rewardSize.MaxTextSize = 15
		end

		tile.Parent = row
		tiles[index] = { Frame = tile, Stroke = stroke, Day = dayLabel, Reward = rewardLabel }
	end

	row.Parent = content

	-- The single claim button, plus the "come back tomorrow" hint that only shows once claimed.
	local claimButton = Components.button({
		Name = "Claim",
		Text = Strings.get("Daily.Claim"),
		Size = UDim2.fromOffset(CLAIM_W, CLAIM_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CLAIM_Y),
		Color = COLORS.Good,
		TextColor = COLORS.Bg,
		TextSize = 22,
		OnClick = function()
			ctx.Remotes:WaitForChild("ClaimDaily"):FireServer()
		end,
		Parent = content,
	})

	local comeBackLabel = Components.label({
		Name = "ComeBack",
		Text = Strings.get("Daily.ComeBack"),
		Size = UDim2.new(0, HINT_W, 0, HINT_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HINT_Y),
		TextSize = 16,
		Color = COLORS.Muted,
		Parent = content,
	})
	comeBackLabel.Visible = false

	-- The rewarded-ad button (plan change I): "📺 Bonus coins" with the "Watch a short ad" disclosure, right of
	-- the Claimed button, only after claiming while an ad is available and today's CoinPouch ad is unused.
	local adAvailable = false
	local adCheckAt = -math.huge
	local adChecking = false
	local adButton = Components.button({
		Name = "BonusAd",
		Text = "",
		Size = UDim2.fromOffset(AD_W, CLAIM_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, AD_SHIFT, 0, CLAIM_Y),
		Color = COLORS.Gold,
		TextColor = COLORS.Bg,
		TextSize = 18,
		OnClick = function()
			task.spawn(function()
				if not ctx.Purchase:RequestAd("CoinPouch") then
					ctx.UI:Toast(Strings.get("Toast.NoAd"))
				end
				adAvailable = false
				adCheckAt = -math.huge
			end)
		end,
		Parent = content,
	})
	adButton.RichText = true
	adButton.Text = Theme.Icons.Ad
		.. " "
		.. Strings.get("Ad.BonusCoins")
		.. '\n<font size="11">'
		.. Strings.get("Ad.Subtitle")
		.. "</font>"
	adButton.Visible = false

	-- Repaints the tiles and the claim button from a snapshot; never rebuilds and never closes the panel.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local streak = if isTable(state.Streak) then state.Streak else {}
		local now = ctx.Now()
		local today = ctx.Logic.WeekId.dateString(now)
		local yesterday = ctx.Logic.WeekId.dateString(now - 86400)
		local day = num(streak.Day, 0)
		local lastClaim = if typeof(streak.LastClaimDate) == "string" then streak.LastClaimDate else ""

		-- Which tile pays out right now: today's if already claimed, tomorrow's if yesterday was claimed.
		local claimedToday = lastClaim == today
		local highlighted = 1
		if claimedToday then
			highlighted = day
		elseif lastClaim == yesterday and day >= 1 then
			highlighted = day + 1
			if highlighted > dayCount then
				highlighted = 1
			end
		end
		if highlighted < 1 or highlighted > dayCount then
			highlighted = 1
		end

		for index, tile in tiles do
			local claimed = if claimedToday then index <= highlighted else index < highlighted
			local isHighlighted = index == highlighted

			tile.Frame.BackgroundColor3 = Theme.color(if isHighlighted then COLORS.Panel else COLORS.PanelLight)
			tile.Stroke.Color = Theme.color(if isHighlighted then COLORS.Gold else COLORS.Stroke)
			tile.Stroke.Thickness = if isHighlighted then 3 else 2

			local transparency = if claimed then 0.4 else 0
			tile.Day.TextTransparency = transparency
			tile.Reward.TextTransparency = transparency
		end

		if claimedToday then
			claimButton.Text = Strings.get("Daily.Claimed")
			Components.setEnabled(claimButton, false)
			claimButton.TextColor3 = Theme.color(COLORS.Muted)
			comeBackLabel.Visible = true
		else
			claimButton.Text = Strings.get("Daily.Claim")
			claimButton:SetAttribute("NormalColor", COLORS.Good)
			Components.setEnabled(claimButton, true)
			claimButton.TextColor3 = Theme.color(COLORS.Bg)
			comeBackLabel.Visible = false
		end

		-- The bonus-ad button: claimed today, not restricted, today's CoinPouch ad unused, and an ad available
		-- (probed at most every AD_RECHECK_SECONDS; one answer covers a single ad).
		local monetization = if isTable(state.Monetization) then state.Monetization else {}
		local counts = if isTable(monetization.AdCounts) then monetization.AdCounts else {}
		local usedToday = counts.Date == today and num(counts.CoinPouch, 0) >= 1
		local wantAd = claimedToday
			and not usedToday
			and not ctx.Purchase:IsRestricted()
			and not ctx.Purchase:IsHidden("Product", "CoinPouchS")
		if wantAd and root.Visible and not adChecking and now - adCheckAt >= AD_RECHECK_SECONDS then
			adChecking = true
			adCheckAt = now
			task.spawn(function()
				adAvailable = ctx.Purchase:CheckAd()
				adChecking = false
				refresh(ctx.State:Get())
			end)
		end
		local showAd = wantAd and adAvailable
		adButton.Visible = showAd
		claimButton.Position = UDim2.new(0.5, if showAd then -AD_SHIFT else 0, 0, CLAIM_Y)
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

	-- The UTC day can roll over while the panel stays open, so re-evaluate once a second.
	task.spawn(function()
		while root.Parent ~= nil do
			task.wait(REFRESH_SECONDS)
			if root.Visible then
				refresh(ctx.State:Get())
			end
		end
	end)

	-- Sensible defaults until the first snapshot arrives: day 1 is the next reward.
	refresh(nil)

	return screen
end

return Daily
