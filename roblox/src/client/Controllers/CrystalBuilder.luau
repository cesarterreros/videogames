--!strict
-- Procedural crystal model builder (plain module, not a controller: no Init/Start).
-- Every prism is exactly two parts: a Neon core plus a Glass shell, so a full crystal costs 2 * count parts.
-- The result is deterministic per (shape, tier): all randomness comes from Random.new(shape) in a fixed order.
-- The returned Model is unparented, named "Crystal", built around the origin with its pivot at the base centre;
-- the caller PivotTo's it onto a pedestal and ScaleTo's it.

local CrystalBuilder = {}

local WHITE = Color3.new(1, 1, 1)

local MIN_TIER = 1
local MAX_TIER = 10
local MIN_PRISMS = 3
local MAX_PRISMS = 7

-- How much lighter the glass shell is than the neon core.
local SHELL_LIGHTEN = 0.35
-- Facet orientation: the core is turned 45 degrees about its long axis so its corners face outward,
-- the shell an extra 22.5 degrees so the two outlines together read as one many-sided prism.
local CORE_SPIN = math.rad(45)
local SHELL_SPIN = math.rad(45 + 22.5)
-- The shell is slightly fatter and taller than the core so it fully encloses it.
local SHELL_PAD_WIDTH = 0.25
local SHELL_PAD_HEIGHT = 0.15
local SHELL_TRANSPARENCY = 0.55

-- Parse a "#RRGGBB" seed colour. A malformed string falls back to white instead of erroring mid-build.
local function parseColor(seedColorHex: string): Color3
	local ok, color = pcall(Color3.fromHex, seedColorHex)
	if ok and typeof(color) == "Color3" then
		return color
	end
	return WHITE
end

-- Create one part with the shared crystal settings (anchored, non-interactive, no shadow, smooth faces).
local function newPart(
	name: string,
	size: Vector3,
	material: Enum.Material,
	color: Color3,
	transparency: number,
	cframe: CFrame
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Add one prism (core + shell) to the model. `baseFrame` maps the prism's base point to the world and
-- orients its long axis; the parts are lifted by half their height so the bottom end sits at that point.
local function addPrism(model: Model, index: number, baseFrame: CFrame, height: number, width: number, color: Color3)
	local partFrame = baseFrame * CFrame.new(0, height / 2, 0)

	local core = newPart(
		"Core_" .. index,
		Vector3.new(width, height, width),
		Enum.Material.Neon,
		color,
		0,
		partFrame * CFrame.Angles(0, CORE_SPIN, 0)
	)
	core.Parent = model

	local shell = newPart(
		"Shell_" .. index,
		Vector3.new(width + SHELL_PAD_WIDTH, height + SHELL_PAD_HEIGHT, width + SHELL_PAD_WIDTH),
		Enum.Material.Glass,
		color:Lerp(WHITE, SHELL_LIGHTEN),
		SHELL_TRANSPARENCY,
		partFrame * CFrame.Angles(0, SHELL_SPIN, 0)
	)
	shell.Parent = model
end

-- Build the crystal for a given seed colour hex, shape seed and tier. Same (shape, tier) always yields
-- the same model. The model is unparented and pivoted at its base centre, all geometry at y >= 0 (base ~y = 0).
function CrystalBuilder.build(seedColorHex: string, shape: number, tier: number): Model
	local color = parseColor(seedColorHex)

	-- Defensive integer/range guards; the caller's contract already promises sane values.
	local safeTier = math.clamp(math.floor(tier), MIN_TIER, MAX_TIER)
	local seed = math.clamp(math.floor(shape), 1, 2147483646)

	local r = Random.new(seed)

	-- Prism count first, then every prism's own rolls in a fixed order, so the draw sequence is stable.
	local count = MIN_PRISMS + r:NextInteger(0, MAX_PRISMS - MIN_PRISMS)
	if safeTier >= 7 then
		count = math.min(MAX_PRISMS, count + 1)
	end

	-- Full size at scale 1: fits a 4-stud pedestal.
	local height = 3 + safeTier * 0.3
	local width = 0.9 + safeTier * 0.05

	local model = Instance.new("Model")
	model.Name = "Crystal"

	-- Prism 1 is the main one: upright at the centre, its base at the origin.
	addPrism(model, 1, CFrame.new(0, 0, 0), height, width, color)

	for i = 2, count do
		local prismHeight = height * r:NextNumber(0.4, 0.8)
		local prismWidth = width * r:NextNumber(0.55, 0.85)
		-- Evenly spread around the base, with a little jitter so clusters never look mechanical.
		local angle = (i - 2) / (count - 1) * 2 * math.pi + r:NextNumber(-0.4, 0.4)
		local offset = r:NextNumber(0.4, 1.1)
		local tilt = r:NextNumber(12, 35)
		local spin = r:NextNumber(0, 2 * math.pi)

		-- The base point sits at -Z in the ring; rotating about local X by -tilt sends the prism's
		-- local +Y toward -Z, i.e. the top leans away from the centre (outward). Then spin about the
		-- long axis for a random facet orientation.
		local baseFrame = CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, -offset)
			* CFrame.Angles(-math.rad(tilt), 0, 0)
			* CFrame.Angles(0, spin, 0)

		addPrism(model, i, baseFrame, prismHeight, prismWidth, color)
	end

	-- Pivot at the base centre; no PrimaryPart, the caller scales and repositions the whole model.
	model.WorldPivot = CFrame.new(0, 0, 0)

	return model
end

-- Collect the "Core_" parts of a built crystal (the renderer recolours these for mutations).
function CrystalBuilder.cores(model: Model): { BasePart }
	local found: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 5) == "Core_" then
			table.insert(found, child)
		end
	end
	return found
end

-- Collect the "Shell_" parts of a built crystal (the renderer recolours these for mutations).
function CrystalBuilder.shells(model: Model): { BasePart }
	local found: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 6) == "Shell_" then
			table.insert(found, child)
		end
	end
	return found
end

return CrystalBuilder
