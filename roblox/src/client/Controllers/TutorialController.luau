--!strict
-- TutorialController.luau - the client half of the 8-step tutorial: it locks the HUD, filters world taps and
-- draws the guidance (beam, world bubble, screen bubble, highlight, popups and the tip card).
-- The server owns the step (snapshot.Tutorial = { Step = last step reached (0..8), Done }); this controller
-- only draws the NEXT action and reports steps 4 (Shop opened) and 8 (tip closed) with TutorialAction.
-- Everything is re-derived from the latest snapshot, so a rejoin mid-tutorial just works.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings.Strings)
local Progression = require(Shared.Config.Progression)
local Growth = require(Shared.Logic.Growth)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local TapController = require(script.Parent.TapController)

local TutorialController = {}

-- The 0.25 s loop re-runs the per-frame parts (bubble text, beam target, hint position).
local LOOP_INTERVAL = 0.25
-- Pedestals are looked up by name "Pedestal_<index>"; scan a few more than any cave can hold.
local PEDESTAL_SCAN = 32

local BUBBLE_SIZE = UDim2.fromOffset(230, 50)
local BUBBLE_OFFSET = Vector3.new(0, 4, 3)
local BUBBLE_TRANSPARENCY = 0.1
-- Half the pedestal height plus a couple of studs above it. Pedestals are cylinders lying on their side, so
-- the footprint's X is what points up in world space.
local BEAM_HEIGHT_PAD = 2

local HINT_SIZE = UDim2.fromOffset(240, 40)
local HINT_Z = 60
local HIGHLIGHT_Z = 59
local POPUP_SIZE = UDim2.fromOffset(300, 56)
local POPUP_Z = 60
local TIP_SIZE = UDim2.fromOffset(360, 150)
local POPUP_BONUS_TIME = 2
local POPUP_LUCKY_TIME = 2.5
local PULSE_TIME = 0.8
local PULSE_TRANSPARENCY = 0.6

local WHITE = Color3.new(1, 1, 1)
local GOLD = Theme.color(Theme.Colors.Gold)

-- Not in Config.Rolls on the client; the Lucky popup only needs the multiplier shown on the result card.
local MUTATION_MULT: { [string]: number } = {
	Glowing = 2,
	Molten = 5,
	Prismatic = 20,
}

local remote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local latest: { [string]: any }? = nil

-- -1 = nothing drawn yet. currentStep is the step whose guidance is on screen right now.
local currentStep = -1
local firstSnapshot = true
local sent: { [number]: boolean } = {}
local bonusShown = false
local luckyShown = false
local dailyOpened = false
-- The last ShatterResult mutation that was not "None"; the step 7 popup names it.
local lastMutation = "Glowing"

-- Visual state, created once and reused.
local beam: Beam? = nil
local fromAttachment: Attachment? = nil
local toAttachment: Attachment? = nil
local bubble: BillboardGui? = nil
local bubbleLabel: TextLabel? = nil
local bubblePart: BasePart? = nil
local hint: Frame? = nil
local hintLabel: TextLabel? = nil
local hintTarget: GuiObject? = nil
local hintPlacement = "below"
local origin: Frame? = nil
local highlight: Frame? = nil
local highlightTarget: GuiObject? = nil
local highlightTween: Tween? = nil
local popup: Frame? = nil
local popupToken = 0
local tipCard: Frame? = nil
local plot: Model? = nil

-- Reads an attribute, falling back to `default` when the stored type is wrong.
local function attr(part: Instance, name: string, default: any): any
	local value = part:GetAttribute(name)
	return if type(value) == type(default) then value else default
end

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera ~= nil then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

-- ---------------------------------------------------------------------------------------------------------
-- Own plot and pedestals
-- ---------------------------------------------------------------------------------------------------------

local function ownPlot(): Model?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local cached = plot
	if cached ~= nil and cached.Parent ~= nil and cached:GetAttribute("OwnerUserId") == player.UserId then
		return cached
	end
	plot = nil
	local map = workspace:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	local plots = map:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, child in plots:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == player.UserId then
			plot = child
			return child
		end
	end
	return nil
end

local function ownPedestal(index: number): BasePart?
	local model = ownPlot()
	if model == nil then
		return nil
	end
	local folder = model:FindFirstChild("Pedestals")
	if folder == nil then
		return nil
	end
	local part = folder:FindFirstChild("Pedestal_" .. index)
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	return part
end

-- Tap filter for steps 5 and 6: any unlocked pedestal of the player's own cave.
local function unlockedFilter(index: number): boolean
	local pedestal = ownPedestal(index)
	return pedestal ~= nil and attr(pedestal, "Unlocked", false) == true
end

local function noTaps(_index: number): boolean
	return false
end

local function onlyFirst(index: number): boolean
	return index == 1
end

-- Step 5 target: the lowest-index pedestal that is unlocked and still empty.
local function firstUnlockedEmpty(): BasePart?
	for index = 1, PEDESTAL_SCAN do
		local pedestal = ownPedestal(index)
		if pedestal ~= nil and attr(pedestal, "Unlocked", false) == true and attr(pedestal, "SeedId", "") == "" then
			return pedestal
		end
	end
	return nil
end

-- Step 6 target: the glowing plant, else the planted one that will be ready first.
local function plantedTarget(): BasePart?
	local glowing: BasePart? = nil
	local earliest: BasePart? = nil
	local earliestReady = math.huge
	for index = 1, PEDESTAL_SCAN do
		local pedestal = ownPedestal(index)
		if pedestal ~= nil then
			if glowing == nil and attr(pedestal, "Mutation", "None") == "Glowing" then
				glowing = pedestal
			end
			if attr(pedestal, "SeedId", "") ~= "" then
				local readyAt = attr(pedestal, "ReadyAt", 0)
				if readyAt < earliestReady then
					earliestReady = readyAt
					earliest = pedestal
				end
			end
		end
	end
	return if glowing ~= nil then glowing else earliest
end

-- ---------------------------------------------------------------------------------------------------------
-- UI lookups
-- ---------------------------------------------------------------------------------------------------------

local function hudButton(name: string): GuiObject?
	local screen: any = UIController:Get("Hud")
	if typeof(screen) ~= "table" then
		return nil
	end
	local buttons: any = screen.Buttons
	if typeof(buttons) ~= "table" then
		return nil
	end
	local button = buttons[name]
	if typeof(button) == "Instance" and button:IsA("GuiObject") then
		return button
	end
	return nil
end

local function shopCard(seedId: string): GuiObject?
	local screen: any = UIController:Get("Shop")
	if typeof(screen) ~= "table" then
		return nil
	end
	local cards: any = screen.Cards
	if typeof(cards) ~= "table" then
		return nil
	end
	local card = cards[seedId]
	if typeof(card) == "Instance" and card:IsA("GuiObject") then
		return card
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- Visuals: beam
-- ---------------------------------------------------------------------------------------------------------

local function ensureFromAttachment(): Attachment?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local existing = root:FindFirstChild("TutorialFrom")
	if existing ~= nil and existing:IsA("Attachment") then
		fromAttachment = existing
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "TutorialFrom"
	attachment.Parent = root
	fromAttachment = attachment
	return attachment
end

-- Points the beam at `pedestal`, or disables it when there is no target.
local function setBeamTarget(pedestal: BasePart?)
	if pedestal == nil then
		if beam ~= nil then
			beam.Enabled = false
		end
		if toAttachment ~= nil and toAttachment.Parent ~= nil then
			toAttachment:Destroy()
		end
		toAttachment = nil
		return
	end

	local existing = pedestal:FindFirstChild("TutorialTo")
	if existing ~= nil and existing:IsA("Attachment") then
		toAttachment = existing
	else
		if toAttachment ~= nil and toAttachment.Parent ~= nil then
			toAttachment:Destroy()
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "TutorialTo"
		attachment.Parent = pedestal
		-- World space: the pedestal cylinder is rotated so its local X is "up"; Size.X / 2 is its half height.
		attachment.WorldPosition = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2 + BEAM_HEIGHT_PAD, 0)
		toAttachment = attachment
	end

	local from = ensureFromAttachment()
	local to = toAttachment
	if from == nil or to == nil then
		if beam ~= nil then
			beam.Enabled = false
		end
		return
	end

	local current = beam
	if current == nil or current.Parent == nil then
		current = Instance.new("Beam")
		current.Name = "TutorialBeam"
		current.Color = ColorSequence.new(GOLD)
		current.Width0 = 0.5
		current.Width1 = 0.5
		current.FaceCamera = true
		current.LightEmission = 1
		current.Segments = 12
		current.CurveSize0 = 4
		current.CurveSize1 = -2
		current.Transparency = NumberSequence.new(0.2)
		-- The beam itself lives somewhere cheap; it only needs its two attachments.
		current.Parent = workspace.Terrain
		beam = current
	end
	current.Attachment0 = from
	current.Attachment1 = to
	current.Enabled = true
end

-- ---------------------------------------------------------------------------------------------------------
-- Visuals: world bubble and screen hint
-- ---------------------------------------------------------------------------------------------------------

local function destroyBubble()
	local target = bubble
	bubble = nil
	bubbleLabel = nil
	bubblePart = nil
	if target ~= nil and target.Parent ~= nil then
		target:Destroy()
	end
end

-- A billboard following `pedestal`. AlwaysOnTop is off: always-on-top billboards did not render in Studio.
local function setWorldBubble(pedestal: BasePart?, text: string?)
	if pedestal == nil or text == nil then
		destroyBubble()
		return
	end
	if bubble == nil or bubble.Parent == nil or bubblePart ~= pedestal then
		destroyBubble()
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "TutorialBubble"
		billboard.Adornee = pedestal
		billboard.AlwaysOnTop = false
		billboard.LightInfluence = 0
		billboard.Size = BUBBLE_SIZE
		billboard.StudsOffset = BUBBLE_OFFSET

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Theme.color(Theme.Colors.Panel)
		label.BackgroundTransparency = BUBBLE_TRANSPARENCY
		label.FontFace = Theme.fontFace()
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.Text = text

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = label

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = GOLD
		stroke.Parent = label

		label.Parent = billboard
		billboard.Parent = pedestal
		bubble = billboard
		bubbleLabel = label
		bubblePart = pedestal
		return
	end
	local label = bubbleLabel
	if label ~= nil then
		label.Text = text
	end
end

-- A zero-size frame at the gui's own (0, 0): its AbsolutePosition turns screen coordinates into gui ones.
local function ensureOrigin(): Frame?
	if origin ~= nil and origin.Parent ~= nil then
		return origin
	end
	local parent = gui
	if parent == nil then
		return nil
	end
	local frame = Instance.new("Frame")
	frame.Name = "TutorialOrigin"
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Position = UDim2.fromOffset(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	origin = frame
	return frame
end

local function destroyHint()
	local frame = hint
	hint = nil
	hintLabel = nil
	hintTarget = nil
	if frame ~= nil and frame.Parent ~= nil then
		frame:Destroy()
	end
end

local function placeHint()
	local frame = hint
	if frame == nil or frame.Parent == nil then
		return
	end
	local target = hintTarget
	if target == nil or target.Parent == nil then
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.fromScale(0.5, 0.9)
		return
	end
	local reference = ensureOrigin()
	local base = if reference ~= nil then reference.AbsolutePosition else Vector2.zero
	local position = target.AbsolutePosition - base
	local size = target.AbsoluteSize
	local above = hintPlacement == "above"
	local x = math.clamp(position.X + size.X / 2, HINT_SIZE.X.Offset / 2 + 8, viewportSize().X - HINT_SIZE.X.Offset / 2)
	frame.AnchorPoint = Vector2.new(0.5, if above then 1 else 0)
	local y = if above then position.Y - 6 else position.Y + size.Y + 6
	frame.Position = UDim2.fromOffset(x, y)
end

-- Shows the screen bubble with `text`. `target` places it (below a HUD button, above the Shop card); with no
-- target it sits at the bottom centre. nil text removes it.
local function setHint(text: string?, target: GuiObject?, placement: string?)
	if text == nil or gui == nil then
		destroyHint()
		return
	end
	local frame = hint
	if frame == nil or frame.Parent == nil then
		if gui == nil then
			return
		end
		frame = Instance.new("Frame")
		frame.Name = "TutorialHint"
		frame.Size = HINT_SIZE
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.BackgroundColor3 = Theme.color(Theme.Colors.Panel)
		frame.ZIndex = HINT_Z

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = GOLD
		stroke.Parent = frame

		local label = Components.label({
			Name = "Text",
			Text = text,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		label.ZIndex = HINT_Z + 1
		frame.Parent = gui
		hint = frame
		hintLabel = label
	else
		local label = hintLabel
		if label ~= nil then
			label.Text = text
		end
	end
	hintTarget = target
	hintPlacement = placement or "below"
	placeHint()
end

-- ---------------------------------------------------------------------------------------------------------
-- Visuals: highlight, popups, tip card
-- ---------------------------------------------------------------------------------------------------------

local function clearHighlight()
	if highlightTween ~= nil then
		highlightTween:Cancel()
		highlightTween = nil
	end
	local frame = highlight
	highlight = nil
	highlightTarget = nil
	if frame ~= nil and frame.Parent ~= nil then
		frame:Destroy()
	end
end

-- Outlines a button or card with a pulsing gold frame; nil removes it.
local function setHighlight(target: GuiObject?)
	if target == nil then
		clearHighlight()
		return
	end
	if highlightTarget == target and highlight ~= nil and highlight.Parent ~= nil then
		return
	end
	clearHighlight()
	if target.Parent == nil then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "TutorialHighlight"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 8, 1, 8)
	frame.Position = UDim2.new(0, -4, 0, -4)
	frame.ZIndex = HIGHLIGHT_Z

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = GOLD
	stroke.Parent = frame

	frame.Parent = target
	highlight = frame
	highlightTarget = target
	highlightTween = TweenService:Create(
		stroke,
		TweenInfo.new(PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = PULSE_TRANSPARENCY }
	)
	highlightTween:Play()
end

local function destroyPopup()
	popupToken += 1
	local frame = popup
	popup = nil
	if frame ~= nil and frame.Parent ~= nil then
		frame:Destroy()
	end
end

-- A short centred line (the tutorial bonus and the Lucky popup).
local function showPopup(text: string, duration: number)
	local parent = gui
	if parent == nil then
		return
	end
	destroyPopup()
	popupToken += 1
	local token = popupToken

	local frame = Instance.new("Frame")
	frame.Name = "TutorialPopup"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.35)
	frame.Size = POPUP_SIZE
	frame.BackgroundColor3 = Theme.color(Theme.Colors.Panel)
	frame.ZIndex = POPUP_Z

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Corner)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = GOLD
	stroke.Parent = frame

	local label = Components.label({
		Name = "Text",
		Text = text,
		Color = Theme.Colors.Gold,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	label.ZIndex = POPUP_Z + 1

	frame.Parent = parent
	popup = frame

	task.delay(duration, function()
		if token ~= popupToken then
			return
		end
		local current = popup
		popup = nil
		if current ~= nil and current.Parent ~= nil then
			current:Destroy()
		end
	end)
end

local function fireOnce(step: number)
	local event = remote
	if event == nil or sent[step] == true then
		return
	end
	sent[step] = true
	event:FireServer(step)
end

local function hideTipCard()
	local frame = tipCard
	tipCard = nil
	if frame ~= nil and frame.Parent ~= nil then
		frame:Destroy()
	end
end

local function showTipCard()
	if tipCard ~= nil and tipCard.Parent ~= nil then
		return
	end
	local parent = gui
	if parent == nil then
		return
	end

	local card = Instance.new("Frame")
	card.Name = "TutorialTip"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = TIP_SIZE
	card.BackgroundColor3 = Theme.color(Theme.Colors.Panel)
	card.ZIndex = HINT_Z

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Corner)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = GOLD
	stroke.Parent = card

	local label = Components.label({
		Name = "Text",
		Text = Strings.get("Tutorial.Tip"),
		TextSize = 22,
		Size = UDim2.new(1, -32, 0, 62),
		Position = UDim2.fromOffset(16, 12),
		Parent = card,
	})
	label.ZIndex = HINT_Z + 1

	Components.button({
		Name = "Ok",
		Text = Strings.get("Tutorial.Ok"),
		Size = UDim2.fromOffset(160, 52),
		Position = UDim2.new(0.5, -80, 1, -64),
		Color = Theme.Colors.Good,
		TextColor = Theme.Colors.Bg,
		OnClick = function()
			hideTipCard()
			fireOnce(8)
		end,
		Parent = card,
	})

	card.Parent = parent
	tipCard = card
end

local function clearVisuals()
	setBeamTarget(nil)
	setWorldBubble(nil, nil)
	setHint(nil)
	setHighlight(nil)
	destroyPopup()
	hideTipCard()
end

-- ---------------------------------------------------------------------------------------------------------
-- Guidance per step
-- ---------------------------------------------------------------------------------------------------------

local function readyText(pedestal: BasePart): string
	local readyAt = attr(pedestal, "ReadyAt", 0)
	local ready = attr(pedestal, "SeedId", "") ~= "" and Growth.isReady(workspace:GetServerTimeNow(), readyAt)
	return Strings.get(if ready then "Tutorial.TapCrystal" else "Tutorial.WatchGrow")
end

-- Re-derives every per-frame visual for the step currently on screen. Safe to call as often as we like.
local function update()
	local step = currentStep
	if step < 0 or step >= 8 then
		return
	end

	if step == 0 or step == 1 then
		local pedestal = ownPedestal(1)
		setBeamTarget(pedestal)
		setWorldBubble(pedestal, Strings.get("Tutorial.TapPedestal"))
		setHint(nil)
		setHighlight(nil)
	elseif step == 2 then
		local pedestal = ownPedestal(1)
		setBeamTarget(pedestal)
		setWorldBubble(pedestal, if pedestal ~= nil then readyText(pedestal) else nil)
		setHint(nil)
		setHighlight(nil)
	elseif step == 3 then
		setBeamTarget(nil)
		setWorldBubble(nil, nil)
		local shopOpen = UIController:OpenPanel() == "Shop"
		local button = if shopOpen then nil else hudButton("Shop")
		setHighlight(button)
		setHint(if button ~= nil then Strings.get("Tutorial.OpenShop") else nil, button, "below")
	elseif step == 4 then
		setBeamTarget(nil)
		setWorldBubble(nil, nil)
		if UIController:OpenPanel() == "Shop" then
			local card = shopCard("Quartz")
			setHighlight(card)
			setHint(if card ~= nil then Strings.get("Tutorial.BuySeeds") else nil, card, "above")
		else
			local button = hudButton("Shop")
			setHighlight(button)
			setHint(if button ~= nil then Strings.get("Tutorial.OpenShop") else nil, button, "below")
		end
	elseif step == 5 then
		local pedestal = firstUnlockedEmpty()
		setBeamTarget(pedestal)
		setWorldBubble(pedestal, Strings.get("Tutorial.PlantThem"))
		setHighlight(nil)
		if UIController:OpenPanel() ~= nil then
			setHint(Strings.get("Tutorial.PlantThem"), nil, "bottom")
		else
			setHint(nil)
		end
	elseif step == 6 then
		local pedestal = plantedTarget()
		setBeamTarget(pedestal)
		setWorldBubble(pedestal, if pedestal ~= nil then readyText(pedestal) else nil)
		setHint(nil)
		setHighlight(nil)
	else
		-- Step 7: the tip card is all that is left. It waits for the Lucky popup to go, and never comes back once
		-- "Got it!" sent step 8 (the loop runs again before the server's reply arrives).
		setBeamTarget(nil)
		setWorldBubble(nil, nil)
		setHint(nil)
		setHighlight(nil)
		if popup == nil and sent[8] ~= true then
			showTipCard()
		end
	end
end

-- The step 7 popup: "Lucky! GLOWING x2" for the mutation the player just found.
local function showLuckyPopup()
	local mutation = lastMutation
	if MUTATION_MULT[mutation] == nil then
		mutation = "Glowing"
	end
	local text = Strings.get("Tutorial.Lucky", {
		mutation = string.upper(Strings.get("Mutation." .. mutation)),
		mult = MUTATION_MULT[mutation] or 2,
	})
	showPopup(text, POPUP_LUCKY_TIME)
end

-- Draws one step: HUD lock, world-tap filter, the entry popups, then the guidance.
local function apply(step: number)
	local previous = currentStep
	currentStep = step

	if step >= 8 then
		UIController:SetLocked(false, nil)
		TapController:SetAllowed(nil)
		clearVisuals()
		-- Finished during this session: send the player to the daily reward once.
		if not dailyOpened and previous >= 0 and previous < 8 then
			dailyOpened = true
			pcall(function()
				UIController:Open("Daily")
			end)
		end
		return
	end

	local allowedButton: string? = nil
	local filter: (index: number) -> boolean = onlyFirst
	if step <= 2 then
		allowedButton = nil
		filter = onlyFirst
	elseif step == 3 or step == 4 then
		allowedButton = "Shop"
		filter = noTaps
	elseif step == 5 or step == 6 then
		allowedButton = "MyCave"
		filter = unlockedFilter
	else
		-- Step 7: nothing left to tap.
		allowedButton = nil
		filter = noTaps
	end
	UIController:SetLocked(true, allowedButton)
	TapController:SetAllowed(filter)

	if step == 3 then
		if previous == 2 and not bonusShown then
			bonusShown = true
			showPopup(Strings.get("Tutorial.Bonus", { coins = Progression.Tutorial.BonusCoins }), POPUP_BONUS_TIME)
		end
		-- The player was already in the Shop when the step landed.
		if UIController:OpenPanel() == "Shop" then
			fireOnce(4)
		end
	elseif step == 7 then
		if previous >= 0 and previous < 7 and not luckyShown then
			luckyShown = true
			showLuckyPopup()
		end
	end

	update()
end

local function safeApply(step: number)
	local ok, err = pcall(apply, step)
	if not ok then
		warn("[Tutorial] " .. tostring(err))
	end
end

-- Draws whatever the latest snapshot says. Called for every snapshot and every panel change.
local function refresh(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	local data: { [string]: any } = snapshot
	latest = data

	local tutorial = data.Tutorial
	if typeof(tutorial) ~= "table" then
		-- No tutorial state at all: make sure nothing is locked or drawn.
		firstSnapshot = false
		safeApply(8)
		return
	end

	local rawStep = tutorial.Step
	local step = if type(rawStep) == "number" then math.clamp(math.floor(rawStep), 0, 8) else 0
	local done = tutorial.Done == true

	if firstSnapshot then
		firstSnapshot = false
		-- Profile already finished: unlock everything and do nothing else.
		if done then
			safeApply(8)
			return
		end
	end

	safeApply(if done then 8 else step)
end

local function safeRefresh(snapshot: any)
	local ok, err = pcall(refresh, snapshot)
	if not ok then
		warn("[Tutorial] " .. tostring(err))
	end
end

-- Nothing to set up. Must not yield.
function TutorialController:Init() end

function TutorialController:Start()
	UIController:WaitUntilReady()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild("TutorialAction") :: RemoteEvent
	gui = Players.LocalPlayer.PlayerGui:WaitForChild("CrystalGroveUI") :: ScreenGui

	-- The Lucky popup names the mutation the player just found.
	local shatterResult = remotes:WaitForChild("ShatterResult") :: RemoteEvent
	shatterResult.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local mutation = payload.mutation
		if type(mutation) == "string" and mutation ~= "" and mutation ~= "None" then
			lastMutation = mutation
		end
	end)

	StateController.Changed:Connect(safeRefresh)
	local existing = StateController:Get()
	if existing ~= nil then
		safeRefresh(existing)
	end

	UIController.PanelOpened:Connect(function(name: any)
		if name == "Shop" and currentStep == 3 then
			fireOnce(4)
		end
		safeRefresh(latest)
	end)
	UIController.PanelClosed:Connect(function()
		safeRefresh(latest)
	end)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		fromAttachment = nil
		safeRefresh(latest)
	end)

	-- The bubble text, beam target and hint position follow the world clock.
	task.spawn(function()
		if not RunService:IsClient() then
			return
		end
		while true do
			task.wait(LOOP_INTERVAL)
			if currentStep >= 0 and currentStep < 8 then
				local ok, err = pcall(update)
				if not ok then
					warn("[Tutorial] " .. tostring(err))
				end
			end
		end
	end)
end

return TutorialController
