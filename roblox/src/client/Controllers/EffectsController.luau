--!strict
-- Client-only shatter feedback: a neon shard burst in the crystal's own colour (tinted by its mutation), a
-- short white flash for Prismatic, coins flying into the HUD counter, a floating "+coins" label and an
-- optional camera shake sized to the crystal (Huge 0.2 s, Colossal 0.4 s). Purely cosmetic: the server has
-- already granted the coins, so nothing here is authoritative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Logic.Format)
local CoinFly = require(Shared.Logic.CoinFly)

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local UIController = require(script.Parent.UIController)
local CrystalRenderer = require(script.Parent.CrystalRenderer)

local EffectsController = {}

local TAU = math.pi * 2
local SHAKE_NAME = "CrystalShake"
-- How far (studs) and how long each big tier throws the camera around.
local SHAKE_AMPLITUDE: { [string]: number } = { Huge = 0.25, Colossal = 0.5 }
local SHAKE_TIME: { [string]: number } = { Huge = 0.2, Colossal = 0.4 }

-- Coin fly: 6-12 icons leave the crystal over FLY_STAGGER_SECONDS and reach the HUD 0.3 s later (0.5 s total).
local FLY_LAYER_NAME = "CoinFly"
local FLY_LAYER_Z = 50
local FLY_ICON_Z = 51 -- every icon and the Prismatic flash sit above the layer itself
local FLY_ICON_SIZE = 26
local FLY_SPREAD = 30 -- px of random offset around the start point
local FLY_STAGGER_SECONDS = 0.2 -- the last icon starts this long after the first
local FLY_SECONDS = 0.3 -- flight time of one icon
local FLASH_SECONDS = 0.25 -- the Prismatic flash fades out over this long
local FLASH_TRANSPARENCY = 0.35 -- how opaque that flash starts
local WHITE = Color3.new(1, 1, 1)
local MOLTEN_TINT = Color3.fromRGB(255, 80, 20)

local TWEEN_SHARD = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FLOAT = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FLY = TweenInfo.new(FLY_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_FLASH = TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Linear)

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

-- The colour of one shard: the crystal's own colour, tinted by its mutation. Prismatic rolls a fresh hue
-- for every shard, so the burst comes out rainbow.
local function shardColor(base: Color3, mutation: any): Color3
	if mutation == "Glowing" then
		return base:Lerp(WHITE, 0.35)
	elseif mutation == "Molten" then
		return base:Lerp(MOLTEN_TINT, 0.55)
	elseif mutation == "Prismatic" then
		return Color3.fromHSV(rng:NextNumber(0, 1), 0.55, 1)
	end
	return base
end

-- Throws a handful of neon shards outward from the crystal, each fading and shrinking as it flies.
local function burst(origin: Vector3, base: Color3, mutation: any)
	local folder = getFolder()
	for _ = 1, rng:NextInteger(6, 10) do
		local s = rng:NextNumber(0.3, 0.6)
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(s, s * 1.6, s)
		shard.Material = Enum.Material.Neon
		shard.Color = shardColor(base, mutation)
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

-- The coin-fly layer: one full-screen, click-through Frame inside the ScreenGui, created once and reused.
-- Returns nil while the UI has not been built yet.
local flyLayer: Frame? = nil

local function getFlyLayer(): Frame?
	local gui = UIController:Gui()
	if gui == nil then
		return nil
	end
	local cached = flyLayer
	if cached ~= nil and cached.Parent ~= nil then
		return cached
	end
	local existing = gui:FindFirstChild(FLY_LAYER_NAME)
	if existing ~= nil and existing:IsA("Frame") then
		flyLayer = existing
		return existing
	end
	local layer = Instance.new("Frame")
	layer.Name = FLY_LAYER_NAME
	layer.Size = UDim2.fromScale(1, 1)
	layer.Position = UDim2.fromScale(0, 0)
	layer.BackgroundTransparency = 1
	layer.Active = false
	layer.ZIndex = FLY_LAYER_Z
	layer.Parent = gui
	flyLayer = layer
	return layer
end

-- A short white flash over the whole screen, used by Prismatic shatters.
local function prismaticFlash()
	local layer = getFlyLayer()
	if layer == nil then
		return
	end
	local flash = Instance.new("Frame")
	flash.Name = "PrismaticFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.Position = UDim2.fromScale(0, 0)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = FLASH_TRANSPARENCY
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.ZIndex = FLY_ICON_Z
	flash.Parent = layer
	TweenService:Create(flash, TWEEN_FLASH, { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, FLASH_SECONDS + 0.1)
end

-- Flies 6-12 coin icons from the shattered crystal into the HUD's coin pill, holding the coins back so the
-- counter ticks up as they land. Does nothing (and holds nothing) when the HUD cannot show the counter.
local function coinFly(origin: Vector3, coins: number)
	local hud: any = UIController:Get("Hud")
	if hud == nil then
		return
	end
	local target = hud.CoinTarget
	if target == nil or target.Visible == false then
		return
	end
	local layer = getFlyLayer()
	if layer == nil then
		return
	end

	local layerOrigin = layer.AbsolutePosition
	local center = layerOrigin + layer.AbsoluteSize * 0.5
	-- WorldToScreenPoint is in screen space, which is what AbsolutePosition is measured in too.
	local startPoint = center
	local camera = workspace.CurrentCamera
	if camera ~= nil then
		local screenPoint = camera:WorldToScreenPoint(origin)
		if screenPoint.Z >= 0 then -- in front of the camera: start where the crystal is drawn
			startPoint = Vector2.new(screenPoint.X, screenPoint.Y)
		end
	end
	local startLocal = startPoint - layerOrigin
	local targetLocal = target.AbsolutePosition + target.AbsoluteSize * 0.5 - layerOrigin

	local count = CoinFly.iconCount(coins)
	if count <= 0 then
		return
	end
	local shares = CoinFly.split(coins, count)

	pcall(function()
		hud.HoldCoins(coins)
	end)

	local font = Theme.fontFace()
	for index = 1, count do
		local icon = Instance.new("TextLabel")
		icon.Name = "CoinIcon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = UDim2.fromOffset(FLY_ICON_SIZE, FLY_ICON_SIZE)
		icon.Position = UDim2.fromOffset(
			startLocal.X + rng:NextNumber(-FLY_SPREAD, FLY_SPREAD),
			startLocal.Y + rng:NextNumber(-FLY_SPREAD, FLY_SPREAD)
		)
		icon.BackgroundTransparency = 1
		icon.Text = Theme.Icons.Coins
		icon.TextScaled = true
		icon.FontFace = font
		icon.ZIndex = FLY_ICON_Z
		icon.Parent = layer

		local goal = UDim2.fromOffset(targetLocal.X, targetLocal.Y)
		task.delay((index - 1) / count * FLY_STAGGER_SECONDS, function()
			if icon.Parent == nil then
				return -- the layer went away with the UI; the HUD's safety net releases the hold
			end
			local tween = TweenService:Create(icon, TWEEN_FLY, { Position = goal })
			tween.Completed:Once(function()
				icon:Destroy()
				pcall(function()
					hud.ReleaseCoins(shares[index])
				end)
			end)
			tween:Play()
		end)
	end
end

-- Offsets the camera by a random, decaying amount for `duration` seconds; any shake already running is replaced.
local function shake(amplitude: number, duration: number)
	pcall(function()
		RunService:UnbindFromRenderStep(SHAKE_NAME)
	end)
	local start = os.clock()
	RunService:BindToRenderStep(SHAKE_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local remaining = math.max(0, 1 - (os.clock() - start) / duration)
		local rx = rng:NextNumber(-amplitude, amplitude) * remaining
		local ry = rng:NextNumber(-amplitude, amplitude) * remaining
		camera.CFrame = camera.CFrame * CFrame.new(rx, ry, 0)
	end)
	task.delay(duration, function()
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
	local mutation = data.mutation
	local amplitude: number? = if type(tier) == "string" then SHAKE_AMPLITUDE[tier] else nil
	local shakeSeconds: number? = if type(tier) == "string" then SHAKE_TIME[tier] else nil

	local ok, err = pcall(function()
		burst(origin, color, mutation)
		floatingCoins(origin, coins)
		if amplitude ~= nil and shakeSeconds ~= nil then
			shake(amplitude, shakeSeconds)
		end
		if mutation == "Prismatic" then
			prismaticFlash()
		end
	end)
	if not ok then
		warn("[Effects] " .. tostring(err))
	end

	-- The coins the server just granted fly into the HUD counter. Never let that error out the handler.
	if coins > 0 then
		local flyOk, flyErr = pcall(coinFly, origin, coins)
		if not flyOk then
			warn("[Effects] coin fly: " .. tostring(flyErr))
		end
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
