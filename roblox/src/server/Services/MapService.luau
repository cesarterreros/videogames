--!strict
-- Builds the whole world procedurally from simple anchored Parts: the ground, the hub disc with the
-- HeartCrystal, six radial paths and six grow-plots (floor, walls, sign, spawn point, 13 pedestals each).
-- Other services depend on the exact names in this hierarchy, so keep them stable.
-- The default Lighting level is set here too (values in Config/Lighting); the final art pass happens in batch 6.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local LightingConfig = require(Shared.Config.Lighting)
local Strings = require(Shared.Strings.Strings)

local MapService = {}

-- Layout constants in studs. The plot frames sit at y = 0, so these are also world heights.
local GROUND_TOP = 0
local FLOOR_TOP = 0.2
local HUB_RADIUS = 40
local PLOT_RADIUS = 120
local PATH_START_RADIUS = 40
local PATH_END_RADIUS = 98
local PLOT_HALF_WIDTH = 32
local PLOT_HALF_DEPTH = 22
local PLOT_WALL_HEIGHT = 18
local WALL_THICKNESS = 2
local PEDESTAL_HEIGHT = 3
local PEDESTAL_DIAMETER = 4
local GOLD_PEDESTAL_FROM = 11

local CRYSTAL_COLOR = Color3.fromRGB(120, 200, 255)
-- Cave surfaces are kept light enough for the brightness levels to show them (see the cave brightness record).
local ROCK_COLOR = Color3.fromRGB(105, 100, 125)
local PEDESTAL_LOCKED_COLOR = Color3.fromRGB(80, 80, 95)
local GROUND_COLOR = Color3.fromRGB(50, 50, 66)
local CAVE_FLOOR_COLOR = Color3.fromRGB(70, 70, 92) -- plot floors and paths
local HUB_FLOOR_COLOR = Color3.fromRGB(80, 80, 104)
local PEDESTAL_UNLOCKED_COLOR = Color3.fromRGB(120, 120, 140)

-- Cylinders have their axis on X, so this stands one upright with Y as the height.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Local (x, z) centre of every pedestal: two rows of five plus the back row of three, 8 studs apart.
local PEDESTAL_SPOTS: { { number } } = {
	{ -16, -6 },
	{ -8, -6 },
	{ 0, -6 },
	{ 8, -6 },
	{ 16, -6 },
	{ -16, 2 },
	{ -8, 2 },
	{ 0, 2 },
	{ 8, 2 },
	{ 16, 2 },
	{ -8, 10 },
	{ 0, 10 },
	{ 8, 10 },
}

-- Every property makePart understands. Anything left nil keeps the Roblox default.
type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Color: Color3?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	Parent: Instance?,
}

-- Part factory for the whole map: always anchored, always smooth-shaded, parented last.
local function makePart(props: PartProps): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Name ~= nil then
		part.Name = props.Name
	end
	if props.Size ~= nil then
		part.Size = props.Size
	end
	if props.CFrame ~= nil then
		part.CFrame = props.CFrame
	end
	if props.Shape ~= nil then
		part.Shape = props.Shape
	end
	if props.Material ~= nil then
		part.Material = props.Material
	end
	if props.Color ~= nil then
		part.Color = props.Color
	end
	if props.Transparency ~= nil then
		part.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		part.CanCollide = props.CanCollide
	end
	if props.CanQuery ~= nil then
		part.CanQuery = props.CanQuery
	end
	if props.CanTouch ~= nil then
		part.CanTouch = props.CanTouch
	end
	if props.Parent ~= nil then
		part.Parent = props.Parent
	end
	return part
end

-- Decorative crystal shard: stands on the hub floor `radius` from the centre and leans `tiltDegrees` outward.
local function makeShard(
	parent: Instance,
	name: string,
	angleDegrees: number,
	radius: number,
	height: number,
	tiltDegrees: number
)
	local angle = math.rad(angleDegrees)
	local tilt = math.rad(tiltDegrees)
	-- Yaw so the shard's local +X points outward, then lean it outward around its own Z axis.
	local rotation = CFrame.Angles(0, angle - math.rad(90), 0) * CFrame.Angles(0, 0, -tilt)
	local base = Vector3.new(math.sin(angle) * radius, FLOOR_TOP, math.cos(angle) * radius)
	local centre = base + (rotation * CFrame.new(0, height / 2, 0)).Position
	makePart({
		Name = name,
		Size = Vector3.new(2, height, 2),
		CFrame = CFrame.new(centre) * rotation,
		Material = Enum.Material.Neon,
		Color = CRYSTAL_COLOR,
		CanCollide = false,
		Parent = parent,
	})
end

-- Flat ground plane; its top face sits exactly at y = 0.
local function buildGround(map: Folder)
	makePart({
		Name = "Ground",
		Size = Vector3.new(360, 1, 360),
		CFrame = CFrame.new(0, GROUND_TOP - 0.5, 0),
		Material = Enum.Material.Slate,
		Color = GROUND_COLOR,
		Parent = map,
	})
end

-- The centrepiece: a stone base, one tall central shard and four smaller shards leaning outward.
local function buildHeartCrystal(hub: Model)
	local crystal = Instance.new("Model")
	crystal.Name = "HeartCrystal"

	-- Stone base: diameter 10, 2 studs tall, standing on the hub floor.
	makePart({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 10, 10),
		CFrame = CFrame.new(0, FLOOR_TOP + 1, 0) * UPRIGHT,
		Material = Enum.Material.Rock,
		Color = ROCK_COLOR,
		Parent = crystal,
	})

	-- Central 4 x 18 x 4 shard on the floor; the only collidable piece and the light source of the hub.
	local core = makePart({
		Name = "Core",
		Size = Vector3.new(4, 18, 4),
		CFrame = CFrame.new(0, FLOOR_TOP + 9, 0),
		Material = Enum.Material.Neon,
		Color = CRYSTAL_COLOR,
		CanCollide = true,
		Parent = crystal,
	})

	local glow = Instance.new("PointLight")
	glow.Color = CRYSTAL_COLOR
	glow.Range = 30
	glow.Brightness = 2
	glow.Parent = core

	-- Four smaller shards around the core, each leaning 15-25 degrees outward.
	makeShard(crystal, "Shard1", 40, 4.5, 11, 16)
	makeShard(crystal, "Shard2", 130, 4.5, 9, 22)
	makeShard(crystal, "Shard3", 220, 4.5, 12, 19)
	makeShard(crystal, "Shard4", 310, 4.5, 8, 25)

	crystal.Parent = hub
end

-- Hub stalls (batch 4): a Seed Shop and an Upgrades stall near the spawn pad, on the side away from the
-- leaderboard board (LeaderboardService puts it 30 degrees round from plot 1's path, radius 34). Each stall faces
-- the spawn pad and carries a ProximityPrompt; the client opens the panel named by the stall's OpensPanel attribute.
local STALL_RADIUS = 30
local STALL_FACES = Vector3.new(0, FLOOR_TOP, 22) -- the HubSpawn pad
local STALLS = {
	{
		Name = "SeedShopStall",
		Angle = -20,
		SignKey = "Stall.SeedShop",
		Panel = "Shop",
		Color = Color3.fromRGB(70, 160, 90),
	},
	{
		Name = "UpgradeStall",
		Angle = -40,
		SignKey = "Stall.Upgrades",
		Panel = "Upgrades",
		Color = Color3.fromRGB(80, 120, 200),
	},
}

-- One stall: a counter, two posts, a coloured roof and a sign whose text ignores scene lighting.
-- The stall frame's -Z (LookVector, the Front face) points at the spawn pad.
local function buildStall(hub: Model, def: { [string]: any })
	local angle = math.rad(def.Angle)
	local base = Vector3.new(math.sin(angle) * STALL_RADIUS, FLOOR_TOP, math.cos(angle) * STALL_RADIUS)
	local frame = CFrame.lookAt(base, STALL_FACES)

	local stall = Instance.new("Model")
	stall.Name = def.Name
	stall:SetAttribute("OpensPanel", def.Panel)

	local counter = makePart({
		Name = "Counter",
		Size = Vector3.new(8, 3, 3),
		CFrame = frame * CFrame.new(0, 1.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(120, 85, 55),
		Parent = stall,
	})
	for _, x in { -3.6, 3.6 } do
		makePart({
			Name = "Post",
			Size = Vector3.new(0.6, 7, 0.6),
			CFrame = frame * CFrame.new(x, 3.5, 1.2),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(100, 70, 45),
			Parent = stall,
		})
	end
	makePart({
		Name = "Roof",
		Size = Vector3.new(9, 0.5, 4),
		CFrame = frame * CFrame.new(0, 7.25, 0.5),
		Material = Enum.Material.Fabric,
		Color = def.Color,
		Parent = stall,
	})
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(7, 1.6, 0.3),
		CFrame = frame * CFrame.new(0, 6.1, -0.2),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(30, 28, 40),
		Parent = stall,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Strings.get(def.SignKey)
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 215, 120)
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StallPrompt"
	prompt.ActionText = Strings.get("Prompt.Open")
	prompt.ObjectText = Strings.get(def.SignKey)
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = counter

	stall.Parent = hub
end

-- The hub: round floor disc, the HeartCrystal and the shared spawn pad.
local function buildHub(map: Folder)
	local hub = Instance.new("Model")
	hub.Name = "Hub"

	-- Round hub floor: 1 stud thick, diameter 80, top face at y = 0.2.
	makePart({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, HUB_RADIUS * 2, HUB_RADIUS * 2),
		CFrame = CFrame.new(0, FLOOR_TOP - 0.5, 0) * UPRIGHT,
		Material = Enum.Material.Slate,
		Color = HUB_FLOOR_COLOR,
		Parent = hub,
	})

	buildHeartCrystal(hub)
	for _, def in STALLS do
		buildStall(hub, def)
	end

	-- Spawn pad on the hub floor, 22 studs from the centre, on the side facing plot 1.
	local hubSpawn = Instance.new("SpawnLocation")
	hubSpawn.Name = "HubSpawn"
	hubSpawn.Anchored = true
	hubSpawn.Size = Vector3.new(8, 1, 8)
	hubSpawn.CFrame = CFrame.new(0, FLOOR_TOP + 0.5, 22)
	hubSpawn.TopSurface = Enum.SurfaceType.Smooth
	hubSpawn.BottomSurface = Enum.SurfaceType.Smooth
	hubSpawn.Neutral = true
	hubSpawn.Duration = 0
	hubSpawn.Transparency = 0.3
	hubSpawn.Material = Enum.Material.Neon
	hubSpawn.Color = Color3.fromRGB(80, 90, 140)
	hubSpawn.CanCollide = true
	hubSpawn.Parent = hub

	hub.Parent = map
end

-- One flat path per plot, running from the hub rim (radius 40) to that plot's entrance (radius 98).
local function buildPaths(map: Folder)
	local paths = Instance.new("Folder")
	paths.Name = "Paths"

	local midRadius = (PATH_START_RADIUS + PATH_END_RADIUS) / 2
	local length = PATH_END_RADIUS - PATH_START_RADIUS

	for index = 1, GameConfig.PlotCount do
		local angle = math.rad((index - 1) * 60)
		local centre = Vector3.new(math.sin(angle) * midRadius, FLOOR_TOP - 0.1, math.cos(angle) * midRadius)
		makePart({
			Name = "Path_" .. index,
			Size = Vector3.new(12, 0.2, length),
			-- Yawing by `angle` makes the part's local +Z point straight out along the plot's direction.
			CFrame = CFrame.new(centre) * CFrame.Angles(0, angle, 0),
			Material = Enum.Material.Slate,
			Color = CAVE_FLOOR_COLOR,
			Parent = paths,
		})
	end

	paths.Parent = map
end

-- Frame of plot `index`: centred at radius 120, local -Z (LookVector) pointing at the hub,
-- so the open front is at local z = -22 and the back wall at local z = +22.
local function plotFrameFor(index: number): CFrame
	local angle = math.rad((index - 1) * 60)
	local centre = Vector3.new(math.sin(angle) * PLOT_RADIUS, 0, math.cos(angle) * PLOT_RADIUS)
	return CFrame.lookAt(centre, Vector3.new(0, 0, 0))
end

-- Back and side walls, the front lintel beam and the ceiling strips that leave the centre open.
local function buildWalls(plotModel: Model, plotFrame: CFrame)
	local walls = Instance.new("Model")
	walls.Name = "Walls"

	local function addWall(name: string, size: Vector3, offset: Vector3)
		makePart({
			Name = name,
			Size = size,
			CFrame = plotFrame * CFrame.new(offset),
			Material = Enum.Material.Rock,
			Color = ROCK_COLOR,
			Parent = walls,
		})
	end

	-- The interior spans x = -32..32 and z = -22..22, so the walls sit just outside those planes.
	local wallCentreY = FLOOR_TOP + PLOT_WALL_HEIGHT / 2
	addWall(
		"BackWall",
		Vector3.new(PLOT_HALF_WIDTH * 2 + WALL_THICKNESS * 2, PLOT_WALL_HEIGHT, WALL_THICKNESS),
		Vector3.new(0, wallCentreY, PLOT_HALF_DEPTH + WALL_THICKNESS / 2)
	)
	addWall(
		"LeftWall",
		Vector3.new(WALL_THICKNESS, PLOT_WALL_HEIGHT, PLOT_HALF_DEPTH * 2),
		Vector3.new(-PLOT_HALF_WIDTH - WALL_THICKNESS / 2, wallCentreY, 0)
	)
	addWall(
		"RightWall",
		Vector3.new(WALL_THICKNESS, PLOT_WALL_HEIGHT, PLOT_HALF_DEPTH * 2),
		Vector3.new(PLOT_HALF_WIDTH + WALL_THICKNESS / 2, wallCentreY, 0)
	)

	-- Lintel: full width beam over the entrance, 3 tall with its bottom at y = 15. Its front face lands at
	-- local z = -23.1 so the Sign sits flush on it.
	addWall("Lintel", Vector3.new(PLOT_HALF_WIDTH * 2, 3, WALL_THICKNESS), Vector3.new(0, 16.5, -PLOT_HALF_DEPTH - 0.1))

	-- Rock ceiling: 8 stud strips along the walls at y = 16..18, overhanging inward, centre left open.
	addWall(
		"CeilingLeft",
		Vector3.new(8, WALL_THICKNESS, PLOT_HALF_DEPTH * 2),
		Vector3.new(-PLOT_HALF_WIDTH + 2, 17, 0)
	)
	addWall(
		"CeilingRight",
		Vector3.new(8, WALL_THICKNESS, PLOT_HALF_DEPTH * 2),
		Vector3.new(PLOT_HALF_WIDTH - 2, 17, 0)
	)
	addWall(
		"CeilingBack",
		Vector3.new(PLOT_HALF_WIDTH * 2 + WALL_THICKNESS * 2, WALL_THICKNESS, 8),
		Vector3.new(0, 17, PLOT_HALF_DEPTH - 2)
	)

	walls.Parent = plotModel
end

-- Sign plate on the front of the lintel with the SurfaceGui the UI paints the owner's name into.
local function buildSign(plotModel: Model, plotFrame: CFrame)
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(24, 4, 0.6),
		CFrame = plotFrame * CFrame.new(0, 16.5, -23.4),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(30, 28, 40),
		Parent = plotModel,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "OwnerName"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
end

-- Invisible marker in front of pedestal 1, with its LookVector pointing at that pedestal (local +Z).
local function buildSpawnPoint(plotModel: Model, plotFrame: CFrame)
	makePart({
		Name = "SpawnPoint",
		Size = Vector3.new(2, 1, 2),
		CFrame = plotFrame * CFrame.new(-16, FLOOR_TOP + 0.5, -15) * CFrame.Angles(0, math.rad(180), 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = plotModel,
	})
end

-- The 13 pedestals of a plot, plus a gold rim on the last three (the "gold" slots).
local function buildPedestals(plotModel: Model, plotFrame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Pedestals"

	-- Cylinders are 3 tall / diameter 4, standing upright with their bottom on the plot floor.
	local centreY = FLOOR_TOP + PEDESTAL_HEIGHT / 2

	for index, spot in PEDESTAL_SPOTS do
		local x = spot[1]
		local z = spot[2]
		local pedestalCFrame = plotFrame * CFrame.new(x, centreY, z) * UPRIGHT

		local pedestal = makePart({
			Name = "Pedestal_" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PEDESTAL_HEIGHT, PEDESTAL_DIAMETER, PEDESTAL_DIAMETER),
			CFrame = pedestalCFrame,
			Material = Enum.Material.Slate,
			Color = PEDESTAL_LOCKED_COLOR,
			Parent = folder,
		})

		-- The dim "locked" look; the growth service recolours a pedestal once it is unlocked and planted.
		pedestal:SetAttribute("Index", index)
		pedestal:SetAttribute("Unlocked", false)
		pedestal:SetAttribute("Gold", index >= GOLD_PEDESTAL_FROM)
		pedestal:SetAttribute("SeedId", "")
		pedestal:SetAttribute("PlantedAt", 0)
		pedestal:SetAttribute("ReadyAt", 0)
		pedestal:SetAttribute("Mutation", "None")
		pedestal:SetAttribute("Shape", 0)

		if index >= GOLD_PEDESTAL_FROM then
			makePart({
				Name = "GoldRim",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, PEDESTAL_DIAMETER + 0.6, PEDESTAL_DIAMETER + 0.6),
				CFrame = plotFrame * CFrame.new(x, FLOOR_TOP + PEDESTAL_HEIGHT, z) * UPRIGHT,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 196, 64),
				CanCollide = false,
				CanQuery = false,
				Parent = pedestal,
			})
		end
	end

	folder.Parent = plotModel
end

-- One plot: floor, walls, sign, spawn point and pedestals, all placed through that plot's frame.
local function buildPlot(index: number): Model
	local plotFrame = plotFrameFor(index)

	local plot = Instance.new("Model")
	plot.Name = "Plot_" .. index

	local floorPart = makePart({
		Name = "Floor",
		Size = Vector3.new(PLOT_HALF_WIDTH * 2, 1, PLOT_HALF_DEPTH * 2),
		CFrame = plotFrame * CFrame.new(0, FLOOR_TOP - 0.5, 0),
		Material = Enum.Material.Slate,
		Color = CAVE_FLOOR_COLOR,
		Parent = plot,
	})

	buildWalls(plot, plotFrame)
	buildSign(plot, plotFrame)
	buildSpawnPoint(plot, plotFrame)
	buildPedestals(plot, plotFrame)

	plot.PrimaryPart = floorPart
	plot.WorldPivot = plotFrame

	-- DataService/PlotService write OwnerUserId; PlotIndex stays fixed for the lifetime of the server.
	plot:SetAttribute("PlotIndex", index)
	plot:SetAttribute("OwnerUserId", 0)

	return plot
end

-- The Plots folder with one model per configured plot.
local function buildPlots(map: Folder)
	local plots = Instance.new("Folder")
	plots.Name = "Plots"

	for index = 1, GameConfig.PlotCount do
		buildPlot(index).Parent = plots
	end

	plots.Parent = map
end

-- Night mood for the whole game: the default brightness level, short fog and a soft bloom on the neon.
-- Each client then applies its player's own level on top (LightingController).
local function setupLighting()
	local preset = LightingConfig.Presets[LightingConfig.Default]
	assert(preset ~= nil, "[MapService] Config/Lighting Default must name a preset")
	Lighting.ClockTime = 0
	Lighting.Brightness = preset.Brightness
	Lighting.ExposureCompensation = preset.ExposureCompensation
	Lighting.Ambient = Color3.fromRGB(preset.Ambient[1], preset.Ambient[2], preset.Ambient[3])
	Lighting.OutdoorAmbient =
		Color3.fromRGB(preset.OutdoorAmbient[1], preset.OutdoorAmbient[2], preset.OutdoorAmbient[3])
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.FogColor = Color3.fromRGB(10, 10, 24)
	Lighting.FogEnd = 600

	-- Reuse an existing Bloom so reloads don't stack effects.
	local existing = Lighting:FindFirstChild("Bloom")
	local bloom: BloomEffect
	if existing ~= nil and existing:IsA("BloomEffect") then
		bloom = existing
	else
		if existing ~= nil then
			existing:Destroy()
		end
		bloom = Instance.new("BloomEffect")
		bloom.Name = "Bloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.8
	bloom.Size = 24
	bloom.Threshold = 0.85
end

-- Builds the entire world plus the Lighting setup. Must not yield: nothing here waits for anything.
function MapService:Init()
	-- The layout table below is hand-written, so make sure it still matches the config.
	assert(
		GameConfig.MaxPedestals == 13 and #PEDESTAL_SPOTS == 13,
		"[MapService] PEDESTAL_SPOTS must describe exactly GameConfig.MaxPedestals (13) pedestals"
	)

	-- Guard against a double build: drop whatever a previous Init left in the workspace.
	local previous = workspace:FindFirstChild("Map")
	if previous ~= nil then
		previous:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildGround(map)
	buildHub(map)
	buildPaths(map)
	buildPlots(map)

	-- Parent last so nothing ever sees a half-built world.
	map.Parent = workspace

	setupLighting()
end

-- Dim stone for locked pedestals, brighter stone for unlocked ones. Used by PlotService and CrystalService.
function MapService.setPedestalLook(pedestal: BasePart, unlocked: boolean)
	pedestal.Color = if unlocked then PEDESTAL_UNLOCKED_COLOR else PEDESTAL_LOCKED_COLOR
end

-- Nothing to start: the map is static and exists entirely after Init.
function MapService:Start() end

return MapService
