--!strict
-- Crystal visuals: mutation effects, the countdown label, the ripe crystal's glow ring and the growth scale curve.
-- The builder makes the model; this module only decorates it. Nothing here yields or talks to the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Graphics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Graphics"))
local CrystalBuilder = require(script.Parent.CrystalBuilder)

local CrystalVisuals = {}

local WHITE = Color3.new(1, 1, 1)
local MOLTEN_TINT = Color3.fromRGB(255, 80, 20)
local MOLTEN_LIGHT = Color3.fromRGB(255, 120, 40)
local EMBER_HOT = Color3.fromRGB(255, 170, 60)
local EMBER_COLD = Color3.fromRGB(255, 60, 20)
local READY_COLOR = Color3.fromRGB(255, 225, 90)

-- Full-quality emitter rates; the graphics profile's ParticleRate scales both.
local SPARKLE_RATE = 4
local EMBER_RATE = 6
local LIGHT_RANGE = 10

-- Removes effects this module added to a part, so a re-apply never stacks them.
local function clearEffects(part: BasePart)
	for _, child in part:GetChildren() do
		if child:IsA("PointLight") or child:IsA("ParticleEmitter") then
			child:Destroy()
		end
	end
end

-- Creates the point light shared by every mutation.
local function makeLight(part: BasePart, color: Color3, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LIGHT_RANGE
	light.Brightness = brightness
	light.Parent = part
	return light
end

-- Creates the sparkle emitter; the texture stays at the engine default. `rate` is already scaled
-- by the graphics profile's ParticleRate.
local function makeSparkles(part: BasePart, color: Color3, rate: number): ParticleEmitter
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Rate = rate
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.25, 0)
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(color:Lerp(WHITE, 0.5))
	sparkles.Parent = part
	return sparkles
end

-- Creates the rising ember emitter used by the Molten mutation (rate already profile-scaled).
local function makeEmbers(part: BasePart, rate: number): ParticleEmitter
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Rate = rate
	embers.Lifetime = NumberRange.new(1, 1.8)
	embers.Speed = NumberRange.new(1, 2.5)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Size = NumberSequence.new(0.18, 0)
	embers.LightEmission = 1
	embers.Color = ColorSequence.new(EMBER_HOT, EMBER_COLD)
	embers.Parent = part
	return embers
end

-- Paints every core and shell of a crystal toward a tint.
local function tint(model: Model, color: Color3, amount: number)
	for _, part in CrystalBuilder.cores(model) do
		part.Color = part.Color:Lerp(color, amount)
	end
	for _, part in CrystalBuilder.shells(model) do
		part.Color = part.Color:Lerp(color, amount)
	end
end

-- A mutated crystal's own light, or nil when the graphics profile drops mutation lights.
local function mutationLight(core: BasePart, color: Color3, profile: Graphics.Profile): PointLight?
	if not profile.MutationLights then
		return nil
	end
	return makeLight(core, color, 1.6)
end

-- Applies a mutation's light and particles; returns them so the caller can animate or remove them.
-- `profile` is a Shared.Config.Graphics profile: it decides which crystals earn a light and how many
-- particles they emit, so a weak device keeps the look but loses the expensive bits.
function CrystalVisuals.applyMutation(
	model: Model,
	mutation: string,
	tier: number,
	color: Color3,
	profile: Graphics.Profile
): (PointLight?, ParticleEmitter?)
	local core = CrystalBuilder.cores(model)[1]
	if core == nil then
		return nil, nil
	end
	clearEffects(core)

	local sparkleRate = SPARKLE_RATE * profile.ParticleRate
	local emberRate = EMBER_RATE * profile.ParticleRate

	if mutation == "Glowing" then
		return mutationLight(core, color, profile), makeSparkles(core, color, sparkleRate)
	elseif mutation == "Molten" then
		tint(model, MOLTEN_TINT, 0.55)
		return mutationLight(core, MOLTEN_LIGHT, profile), makeEmbers(core, emberRate)
	elseif mutation == "Prismatic" then
		return mutationLight(core, color, profile), makeSparkles(core, WHITE, sparkleRate)
	elseif tier >= profile.LightsMinTier then
		return makeLight(core, color, 1.2), nil
	end

	return nil, nil
end

-- Rotates a prismatic crystal's hue over time; the light follows the core colour.
function CrystalVisuals.setPrismaticHue(model: Model, light: PointLight?, hue: number)
	local coreColor = Color3.fromHSV(hue, 0.55, 1)
	for _, part in CrystalBuilder.cores(model) do
		part.Color = coreColor
	end
	for _, part in CrystalBuilder.shells(model) do
		part.Color = Color3.fromHSV(hue, 0.3, 1)
	end
	if light ~= nil then
		light.Color = coreColor
	end
end

-- Creates the countdown billboard above a pedestal and returns its text label.
function CrystalVisuals.makeLabel(pedestal: BasePart): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Countdown"
	gui.Adornee = pedestal
	gui.Size = UDim2.fromScale(6.5, 2)
	CrystalVisuals.placeLabel(gui, pedestal, 8.5) -- the renderer moves it to the crystal's top each tick
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = pedestal

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = WHITE
	label.Text = ""
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	return gui, label
end

-- Moves the countdown billboard to `height` studs above the pedestal's centre (world up).
function CrystalVisuals.placeLabel(gui: BillboardGui, pedestal: BasePart, height: number)
	-- StudsOffsetWorldSpace is measured along the adornee's own axes, and pedestals are
	-- cylinders rolled 90° (their local Y points sideways), so convert world-up first.
	gui.StudsOffsetWorldSpace = pedestal.CFrame:VectorToObjectSpace(Vector3.new(0, height, 0))
end

-- Creates the soft glow ring round a ripe crystal's base. It hangs off the pedestal, never the crystal
-- model (the model gets ScaleTo, which would stretch the ring with it).
function CrystalVisuals.makeReadyRing(pedestal: BasePart, color: Color3): Part
	local ring = Instance.new("Part")
	ring.Name = "ReadyRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color:Lerp(WHITE, 0.4)
	ring.Transparency = 0.5
	-- Pedestals are cylinders rolled 90°, so their local X axis is world up and the disc lies in their
	-- YZ plane. Lift it to just under the top face so only the rim shows round the edge, and size it a
	-- little wider than the pedestal.
	ring.Size = Vector3.new(0.2, pedestal.Size.Y + 1.2, pedestal.Size.Z + 1.2)
	ring.CFrame = pedestal.CFrame * CFrame.new(pedestal.Size.X / 2 - 0.12, 0, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = pedestal
	return ring
end

-- Breathes the ready ring; the renderer calls this from its per-frame heartbeat.
function CrystalVisuals.pulseRing(ring: BasePart, clock: number)
	ring.Transparency = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(clock * 3))
end

-- Sets a label's text (only when it changed) and its ready/not-ready colour.
function CrystalVisuals.setLabel(label: TextLabel, text: string, ready: boolean)
	if label.Text ~= text then
		label.Text = text
	end
	local color = if ready then READY_COLOR else WHITE
	if label.TextColor3 ~= color then
		label.TextColor3 = color
	end
end

-- Scale for a crystal: eases out from 0.15 to 1 while growing, pulses gently once ripe.
function CrystalVisuals.scaleFor(
	now: number,
	plantedAt: number,
	readyAt: number,
	ready: boolean,
	overgrowth: number,
	clock: number
): number
	if ready then
		return (1 + overgrowth) * (1 + 0.04 * math.sin(clock * 4))
	end

	local span = readyAt - plantedAt
	local progress = if span <= 0 then 1 else math.clamp((now - plantedAt) / math.max(span, 1e-6), 0, 1)
	return 0.15 + 0.85 * (1 - (1 - progress) ^ 3)
end

return CrystalVisuals
