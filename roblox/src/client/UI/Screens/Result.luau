--!strict
-- Result.luau - the non-blocking shatter result popup: up to three small cards stacked along the top of the
-- screen, newest on the left. Each card pops in, sits for two seconds and fades away. Nothing here blocks
-- input (the root and the stack are Active = false) and the screen keeps no remotes.

local TweenService = game:GetService("TweenService")

-- Pixel layout.
local CARD_W = 140
local CARD_H = 70
local GAP = 8 -- gap between neighbouring cards
local MAX_CARDS = 3
local STACK_TOP = 96 -- distance of the stack from the top of the safe area
local LINE_1_Y = 4
local LINE_1_H = 26
local LINE_2_Y = 32
local LINE_2_H = 18
local LINE_3_Y = 52
local LINE_3_H = 18
local INSTANT_H = 30 -- extra card height for the two-line instant-grown note
local LINE_4_Y = 72
local LINE_4_H = 26
local BADGE_W = 90
local BADGE_H = 18

-- Timing.
local POP_SECONDS = 0.15
local POP_FROM = 0.6
local LIFE_SECONDS = 2
local FADE_SECONDS = 0.3

-- Fallbacks when Config is missing an entry.
local FALLBACK_PITCH_STEP = 0.05
local FALLBACK_MULT = 1

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

local Result = {}

-- Builds the result cards layer inside ctx.Gui and returns the standard screen table.
function Result.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local Format = ctx.Logic.Format
	local COLORS = Theme.Colors

	-- Guards every value read from a ShatterResult payload.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	local function num(value: any, fallback: number): number
		if typeof(value) == "number" then
			return value
		end
		return fallback
	end

	local function str(value: any, fallback: string): string
		if typeof(value) == "string" then
			return value
		end
		return fallback
	end

	local function hexOr(value: any, fallback: string): string
		if typeof(value) == "string" then
			return value
		end
		return fallback
	end

	-- 1. Root and stack: transparent, non-interactive, always visible.
	local root = Instance.new("Frame")
	root.Name = "Result"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.Visible = true

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, STACK_TOP)
	stack.Size = UDim2.new(0, MAX_CARDS * CARD_W + (MAX_CARDS - 1) * GAP, 0, CARD_H)
	stack.BackgroundTransparency = 1
	stack.Active = false

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Horizontal
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stackLayout.Padding = UDim.new(0, GAP)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = stack

	stack.Parent = root

	-- Cards currently on screen, newest first. The matching LayoutOrder counts down so the newest card
	-- (lowest order) sits leftmost under the horizontal list layout.
	local cards: { Frame } = {}
	local nextOrder = 0

	local function forget(card: Frame)
		for index, existing in cards do
			if existing == card then
				table.remove(cards, index)
				return
			end
		end
	end

	-- Fades every label (and the glyph stroke of each label) along with the card background.
	local function fadeCard(card: Frame)
		if card.Parent == nil then
			return
		end
		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(card, info, { BackgroundTransparency = 1 }):Play()
		for _, child in card:GetChildren() do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				TweenService:Create(child, info, { TextTransparency = 1 }):Play()
			end
			if child:IsA("UIStroke") then
				TweenService:Create(child, info, { Transparency = 1 }):Play()
			end
			local labelStroke = child:FindFirstChildOfClass("UIStroke")
			if labelStroke and (child:IsA("TextLabel") or child:IsA("TextButton")) then
				TweenService:Create(labelStroke, info, { Transparency = 1 }):Play()
			end
		end
		task.delay(FADE_SECONDS, function()
			forget(card)
			if card.Parent ~= nil then
				card:Destroy()
			end
		end)
	end

	-- Which multiplier band a mutation name belongs to, for the "Glowing ×2" line.
	local function mutationMult(mutation: string): number
		local rolls = ctx.Config.Rolls
		local bands = if isTable(rolls) then rolls.Mutation else nil
		if isTable(bands) then
			for _, band in bands do
				if isTable(band) and band.Name == mutation then
					return num(band.Mult, FALLBACK_MULT)
				end
			end
		end
		return FALLBACK_MULT
	end

	-- The tier of the seed that shattered, which sets the pitch of the Shatter sound.
	local function seedTier(seedId: any): number
		if typeof(seedId) ~= "string" then
			return 1
		end
		local seeds = ctx.Config.Seeds
		if isTable(seeds) then
			for _, seed in seeds do
				if isTable(seed) and seed.Id == seedId then
					return num(seed.Tier, 1)
				end
			end
		end
		return 1
	end

	-- Colour of the size word on line 2.
	local function sizeColor(sizeTier: string): string
		if sizeTier == "Big" then
			return hexOr(COLORS.Rarity.Uncommon, COLORS.Text)
		elseif sizeTier == "Huge" then
			return hexOr(COLORS.Rarity.Epic, COLORS.Text)
		elseif sizeTier == "Colossal" then
			return hexOr(COLORS.Rarity.Legendary, COLORS.Text)
		end
		return COLORS.Text
	end

	-- Builds and shows one card for a ShatterResult payload.
	local function addCard(result: any)
		local pedestal = num(result.pedestal, 0)
		local coins = num(result.coins, 0)
		local carats = num(result.carats, 0)
		local mutation = str(result.mutation, "None")
		local sizeTier = str(result.sizeTier, "Normal")
		local newBest = result.newBest == true
		local bonusCoins = num(result.bonusCoins, 0)
		local instantGrown = result.instantGrown == true

		local card = Instance.new("Frame")
		card.Name = "Card" .. tostring(pedestal)
		card.Size = UDim2.fromOffset(CARD_W, if instantGrown then CARD_H + INSTANT_H else CARD_H)
		card.BackgroundColor3 = Theme.color(COLORS.Panel)
		card.BorderSizePixel = 0
		card.Active = false
		card.LayoutOrder = nextOrder
		nextOrder -= 1

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = Theme.color(if newBest then COLORS.Gold else COLORS.Stroke)
		stroke.Parent = card

		-- Line 1: the coins this crystal paid out.
		Components.label({
			Name = "Coins",
			Text = Strings.get("Result.Coins", { coins = Format.compact(coins) }),
			Size = UDim2.new(1, -8, 0, LINE_1_H),
			Position = UDim2.fromOffset(4, LINE_1_Y),
			Color = COLORS.Gold,
			Parent = card,
		})

		-- Line 2: carats, plus the size word when the crystal grew past Normal.
		local sizeKey = "Result.Size." .. sizeTier
		local sizeText = if sizeTier ~= "Normal" then "  " .. Strings.get(sizeKey) else ""
		Components.label({
			Name = "Carats",
			Text = Format.carats(carats) .. sizeText,
			Size = UDim2.new(1, -8, 0, LINE_2_H),
			Position = UDim2.fromOffset(4, LINE_2_Y),
			Color = sizeColor(sizeTier),
			Parent = card,
		})

		-- Line 3: the single loudest fact, first match wins: best ever, then mutation, then bonus coins.
		local hasMutation = mutation ~= "None"
		local hasBonus = bonusCoins > 0
		local mutationKey = "Mutation." .. mutation
		local mutationName = Strings.get(mutationKey)
		local loudFacts = (if newBest then 1 else 0) + (if hasMutation then 1 else 0) + (if hasBonus then 1 else 0)

		local line3Color = COLORS.Muted
		local line3Text = ""
		if newBest then
			line3Text = Strings.get("Result.NewBest")
			line3Color = COLORS.Gold
		elseif hasMutation then
			line3Text = Strings.get("Result.Mutation", { mutation = mutationName, mult = mutationMult(mutation) })
			line3Color = hexOr(COLORS.Rarity.Epic, COLORS.Text)
		elseif hasBonus then
			line3Text = Strings.get("Result.Bonus", { coins = Format.compact(bonusCoins) })
			line3Color = COLORS.Good
		end

		Components.label({
			Name = "Detail",
			Text = line3Text,
			Size = UDim2.new(1, -8, 0, LINE_3_H),
			Position = UDim2.fromOffset(4, LINE_3_Y),
			Color = line3Color,
			Parent = card,
		})

		-- Guardrail 2: an instant-grown crystal doesn't count for the weekly board; say so on its card.
		if instantGrown then
			local note = Components.label({
				Name = "InstantGrown",
				Text = Strings.get("Result.InstantGrown"),
				Size = UDim2.new(1, -8, 0, LINE_4_H),
				Position = UDim2.fromOffset(4, LINE_4_Y),
				Color = COLORS.Muted,
				Parent = card,
			})
			local noteSize = note:FindFirstChildOfClass("UITextSizeConstraint")
			if noteSize ~= nil then
				noteSize.MaxTextSize = 11
			end
		end

		-- Two loud facts at once: hang a small mutation pill on the card's top edge so nothing is hidden.
		if loudFacts > 1 and hasMutation then
			local badge = Components.label({
				Name = "MutationBadge",
				Text = mutationName,
				Size = UDim2.fromOffset(BADGE_W, BADGE_H),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Color = hexOr(COLORS.Rarity.Epic, COLORS.Text),
				Parent = card,
			})
			badge.BackgroundColor3 = Theme.color(COLORS.Panel)
			badge.BackgroundTransparency = 0
			badge.ZIndex = 3

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0.5, 0)
			badgeCorner.Parent = badge
		end

		-- Pop in from 60% scale with a little overshoot.
		local scale = Instance.new("UIScale")
		scale.Scale = POP_FROM
		scale.Parent = card

		-- A 4th card pushes the oldest off the stack at once.
		if #cards >= MAX_CARDS then
			local oldest = cards[#cards]
			table.remove(cards, #cards)
			if oldest then
				oldest:Destroy()
			end
		end

		card.Parent = stack
		table.insert(cards, 1, card) -- newest first

		TweenService
			:Create(scale, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()

		task.delay(LIFE_SECONDS, function()
			fadeCard(card)
		end)
	end

	-- Screens ignore anything that is not a table payload.
	local function open(args: any?)
		if not isTable(args) then
			return
		end
		local result = args :: any

		local tier = seedTier(result.seedId)
		local sounds = ctx.Config.Sounds
		local pitchStep = if isTable(sounds)
			then num(sounds.ShatterPitchStep, FALLBACK_PITCH_STEP)
			else FALLBACK_PITCH_STEP
		ctx.Sounds:Play("Shatter", 1 + pitchStep * (tier - 1))
		ctx.Sounds:Play("Coin")
		if str(result.mutation, "None") ~= "None" then
			ctx.Sounds:Play("Mutation")
		end
		if result.newBest == true then
			ctx.Sounds:Play("NewBest")
		end

		addCard(result)
	end

	local screen: Screen = {
		Root = root,
		Open = open,
		Close = function()
			for _, card in cards do
				card:Destroy()
			end
			table.clear(cards)
		end,
		Update = function(_snapshot: any) end,
		IsOpen = function(): boolean
			return #cards > 0
		end,
	}

	-- Everything is built, so attach the layer last.
	root.Parent = ctx.Gui

	return screen
end

return Result
