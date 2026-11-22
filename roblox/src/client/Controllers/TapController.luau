--!strict
-- Lets the player tap (touch) or click (mouse) their own crystals and pedestals in the world: a ready
-- crystal shatters, a growing one shows a countdown bubble, an empty pedestal opens the seed picker.
-- The client only reads pedestal attributes and fires Shatter; the server decides what actually happens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings.Strings)
local Format = require(Shared.Logic.Format)
local Growth = require(Shared.Logic.Growth)
local UIController = require(script.Parent.UIController)

local TapController = {}

-- Which camera method turns a screen point into a ray, per input kind. Mouse locations are in full-viewport
-- coordinates (they include the GUI inset), touch taps arrive already inset-free. Both are in one table so a
-- Studio test can swap them and check either path.
-- stylua: ignore
local RAY_FUNCTION: { mouse: string, touch: string } = {
	mouse = "ViewportPointToRay",
	touch = "ScreenPointToRay",
}

-- How far a tap reaches, the per-pedestal shatter re-fire guard, and the bubble's life and refresh rate.
local RAY_LENGTH = 500
local SHATTER_COOLDOWN = 1
local BUBBLE_TIME = 2
local BUBBLE_REFRESH = 0.25

-- Bubble look: a small dark plate floating above the pedestal.
local BUBBLE_SIZE = UDim2.fromOffset(150, 40)
-- Just above the pedestal top and 3 studs toward the camera (StudsOffset Z is in camera space), so it sits in front
-- of the crystal. Higher up it ended behind the HUD at close range, and an AlwaysOnTop bubble never showed in Studio.
local BUBBLE_OFFSET = Vector3.new(0, 2, 3)
local BUBBLE_BACKGROUND = Color3.fromRGB(20, 18, 43)
local BUBBLE_TRANSPARENCY = 0.15
local BUBBLE_CORNER = 10
local WHITE = Color3.new(1, 1, 1)

type Bubble = { gui: BillboardGui, token: number }

local remote: RemoteEvent? = nil
local allowed: ((number) -> boolean)? = nil
local cooldowns: { [number]: number } = {}
local bubbles: { [BasePart]: Bubble } = {}
local bubbleToken = 0
-- When the last panel closed (os.clock). The backdrop closes a panel on release, and TouchTapInWorld fires after
-- the release, when the backdrop is already hidden: without this guard that same tap would also hit the world.
local lastPanelClose = -math.huge
local PANEL_CLOSE_GRACE = 0.4

-- Reads an attribute, falling back to `default` when the stored type is wrong.
local function attr(part: Instance, name: string, default: any): any
	local value = part:GetAttribute(name)
	return if type(value) == type(default) then value else default
end

-- Kills a pedestal's bubble; when `token` is given, only if it is still that bubble.
local function stopBubble(pedestal: BasePart, token: number?)
	local bubble = bubbles[pedestal]
	if bubble == nil or (token ~= nil and bubble.token ~= token) then
		return
	end
	bubbles[pedestal] = nil
	local gui = bubble.gui
	if gui.Parent ~= nil then
		gui:Destroy()
	end
end

-- Shows (or restarts) the "ready in ..." bubble on a pedestal, re-reading the server clock every 0.25 s.
local function showBubble(pedestal: BasePart, readyAt: number)
	stopBubble(pedestal)
	bubbleToken += 1
	local token = bubbleToken

	local gui = Instance.new("BillboardGui")
	gui.Name = "TapBubble"
	gui.Adornee = pedestal
	gui.AlwaysOnTop = false
	gui.Size = BUBBLE_SIZE
	gui.StudsOffset = BUBBLE_OFFSET
	gui.LightInfluence = 0
	gui.Parent = pedestal

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = BUBBLE_BACKGROUND
	label.BackgroundTransparency = BUBBLE_TRANSPARENCY
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = ""
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, BUBBLE_CORNER)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	bubbles[pedestal] = { gui = gui, token = token }

	task.spawn(function()
		local deadline = os.clock() + BUBBLE_TIME
		while os.clock() < deadline do
			local bubble = bubbles[pedestal]
			if bubble == nil or bubble.token ~= token then
				return
			end
			local remaining = readyAt - workspace:GetServerTimeNow()
			label.Text = Strings.get("Bubble.Growing", { time = Format.countdown(remaining) })
			task.wait(BUBBLE_REFRESH)
		end
		stopBubble(pedestal, token)
	end)
end

-- The pedestal a tap hit: a BasePart sitting inside a plot's "Pedestals" folder (crystal models are its children).
local function findPedestal(hit: Instance): BasePart?
	local node: Instance? = hit
	while node ~= nil do
		local parent = node.Parent
		if node:IsA("BasePart") and parent ~= nil and parent.Name == "Pedestals" then
			return node
		end
		node = parent
	end
	return nil
end

-- Fires Shatter for a ready crystal, at most once a second per pedestal.
local function shatter(index: number)
	local now = os.clock()
	local last = cooldowns[index]
	if last ~= nil and now - last < SHATTER_COOLDOWN then
		return
	end
	local event = remote
	if event == nil then
		return
	end
	cooldowns[index] = now
	event:FireServer(index)
end

-- Acts on a pedestal's attributes: shatter a ripe crystal, bubble a growing one, or open the seed picker.
local function tapPedestal(pedestal: BasePart, index: number)
	if attr(pedestal, "Unlocked", false) ~= true then
		return
	end
	local seedId = attr(pedestal, "SeedId", "")
	if seedId == "" then
		UIController:Open("SeedPicker", index)
		return
	end
	local readyAt = attr(pedestal, "ReadyAt", 0)
	if Growth.isReady(workspace:GetServerTimeNow(), readyAt) then
		shatter(index)
	else
		showBubble(pedestal, readyAt)
	end
end

-- Turns a screen point into a ray, finds the pedestal under it and handles it. Only the local player's own
-- plot reacts, so tapping another player's cave does nothing.
local function handleScreenPoint(point: Vector2, kind: "mouse" | "touch")
	-- A tap that opens, closes or lands behind a panel is not a world tap.
	if UIController:OpenPanel() ~= nil or os.clock() - lastPanelClose < PANEL_CLOSE_GRACE then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local method = RAY_FUNCTION[kind]
	local ray = (camera :: any)[method](camera, point.X, point.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		table.insert(filter, character)
	end
	local effects = workspace:FindFirstChild("ClientEffects")
	if effects ~= nil then
		table.insert(filter, effects)
	end
	params.FilterDescendantsInstances = filter

	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	if result == nil then
		return
	end
	local pedestal = findPedestal(result.Instance)
	if pedestal == nil then
		return
	end
	local plot = pedestal.Parent.Parent
	if not plot:IsA("Model") or plot:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
		return
	end
	local index = attr(pedestal, "Index", 0)
	if index <= 0 then
		return
	end
	local filterFn = allowed
	if filterFn ~= nil and not filterFn(index) then
		return
	end
	tapPedestal(pedestal, index)
end

-- handleScreenPoint, but a bad attribute or a missing instance can never break the input connections.
local function safeHandleScreenPoint(point: Vector2, kind: "mouse" | "touch")
	local ok, err = pcall(handleScreenPoint, point, kind)
	if not ok then
		warn("[Tap] " .. tostring(err))
	end
end

-- Nothing to set up. Must not yield.
function TapController:Init() end

function TapController:Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:WaitForChild("Shatter") :: RemoteEvent
	UIController.PanelClosed:Connect(function()
		lastPanelClose = os.clock()
	end)

	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if processedByUI then
			return
		end
		safeHandleScreenPoint(position, "touch")
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			safeHandleScreenPoint(UserInputService:GetMouseLocation(), "mouse")
		end
	end)
end

-- Tutorial hook: while set, taps on pedestals whose index the predicate rejects are ignored. nil allows all.
function TapController:SetAllowed(fn: ((index: number) -> boolean)?)
	allowed = fn
end

-- Studio-test entry point: pretends the player tapped `point` with the given input kind.
function TapController:HandleScreenPoint(point: Vector2, kind: "mouse" | "touch")
	safeHandleScreenPoint(point, kind)
end

return TapController
