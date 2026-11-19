--!strict
-- Client-only shatter feedback: a neon shard burst, a floating "+coins" label and an optional camera shake.
-- Purely cosmetic: the server has already granted the coins, so nothing here is authoritative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)

local CrystalRenderer = require(script.Parent.CrystalRenderer)

local EffectsController = {}

local TAU = math.pi * 2
local SHAKE_NAME = "CrystalShake"
local SHAKE_TIME = 0.4
local SHAKE_AMPLITUDE: { [string]: number } = { Huge = 0.25, Colossal = 0.5 }

local TWEEN_SHARD = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FLOAT = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local rng = Random.new()
local effectsFolder: Folder? = nil

-- The client-only folder every temporary effect lives in; created once.
local function getFolder(): Folder
	local cached = effectsFolder
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	local existing = workspace:FindFirstChild("ClientEffects")
	if existing ~= nil and existing:IsA("Folder") then
		effectsFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace
	effectsFolder = folder
	return folder
end

-- Random three-axis rotation for scattering shards.
local function randomAngles(): CFrame
	return CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU))
end

-- Throws a handful of neon shards outward from the crystal, each fading and shrinking as it flies.
local function burst(origin: Vector3, color: Color3)
	local folder = getFolder()
	for _ = 1, rng:NextInteger(6, 10) do
		local s = rng:NextNumber(0.3, 0.6)
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(s, s * 1.6, s)
		shard.Material = Enum.Material.Neon
		shard.Color = color
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.CFrame = CFrame.new(origin) * randomAngles()
		shard.Parent = folder

		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1), rng:NextNumber(-1, 1)).Unit
		local target = CFrame.new(origin + dir * rng:NextNumber(4, 8)) * randomAngles()
		local goals = { CFrame = target, Transparency = 1, Size = shard.Size * 0.3 }
		TweenService:Create(shard, TWEEN_SHARD, goals):Play()
		Debris:AddItem(shard, 1.2)
	end
end

-- Floats "+coins" up from the crystal, then fades the text and its outline away.
local function floatingCoins(origin: Vector3, coins: number)
	local part = Instance.new("Part")
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(origin + Vector3.new(0, 1, 0))
	part.Parent = getFolder()

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 2)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = "+" .. Format.compact(coins)
	label.TextColor3 = Color3.fromRGB(255, 215, 80)
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	TweenService:Create(part, TWEEN_FLOAT, { CFrame = part.CFrame + Vector3.new(0, 4, 0) }):Play()
	task.delay(0.5, function()
		TweenService:Create(label, TWEEN_FADE, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TWEEN_FADE, { Transparency = 1 }):Play()
	end)
	Debris:AddItem(part, 1.4)
end

-- Offsets the camera by a random, decaying amount for 0.4 s; any shake already running is replaced.
local function shake(amplitude: number)
	pcall(function()
		RunService:UnbindFromRenderStep(SHAKE_NAME)
	end)
	local start = os.clock()
	RunService:BindToRenderStep(SHAKE_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local remaining = math.max(0, 1 - (os.clock() - start) / SHAKE_TIME)
		local rx = rng:NextNumber(-amplitude, amplitude) * remaining
		local ry = rng:NextNumber(-amplitude, amplitude) * remaining
		camera.CFrame = camera.CFrame * CFrame.new(rx, ry, 0)
	end)
	task.delay(SHAKE_TIME, function()
		pcall(function()
			RunService:UnbindFromRenderStep(SHAKE_NAME)
		end)
	end)
end

-- Validates the server payload, then plays the burst, the coin label and (for big tiers) the shake.
local function onResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local data: { [string]: any } = payload
	local index = data.pedestal
	local coins = data.coins
	if type(index) ~= "number" or type(coins) ~= "number" then
		return
	end

	local pedestal = CrystalRenderer:GetOwnPedestal(index)
	if pedestal == nil then
		return
	end

	local color = CrystalRenderer:GetLastColor(index) or Color3.new(1, 1, 1)
	local origin = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2 + 1.5, 0)
	local tier = data.sizeTier
	local amplitude: number? = if type(tier) == "string" then SHAKE_AMPLITUDE[tier] else nil

	local ok, err = pcall(function()
		burst(origin, color)
		floatingCoins(origin, coins)
		if amplitude ~= nil then
			shake(amplitude)
		end
	end)
	if not ok then
		warn("[Effects] " .. tostring(err))
	end

	if RunService:IsStudio() then
		local line = string.format(
			"[Shatter] pedestal=%d +%d coins %.2f ct %s %s newBest=%s",
			index,
			coins,
			tonumber(data.carats) or 0,
			tostring(data.mutation),
			tostring(tier),
			tostring(data.newBest)
		)
		print(line)
	end
end

-- Nothing to set up. Must not yield.
function EffectsController:Init() end

-- Subscribes to the per-player shatter result remote.
function EffectsController:Start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShatterResult") :: RemoteEvent
	remote.OnClientEvent:Connect(onResult)
end

return EffectsController
