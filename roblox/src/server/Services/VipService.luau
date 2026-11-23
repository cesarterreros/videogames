--!strict
-- VIP cosmetics: a gold "VIP" name tag (BillboardGui) and a gold sparkle Trail for owners of the VIP pass.
-- Applied on every spawn and as soon as ownership is confirmed. Cosmetic only, no gameplay effect.
-- AlwaysOnTop is false on purpose: AlwaysOnTop billboards didn't show in Studio captures, and the tag
-- should hide behind walls.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PassService = require(script.Parent.PassService)

local VipService = {}

local IS_STUDIO = RunService:IsStudio()

local GOLD = Color3.fromRGB(255, 200, 60)
local TAG_NAME = "VipTag"
local TRAIL_NAME = "VipTrail"
local ATTACH_TOP = "VipTrailTop"
local ATTACH_BOTTOM = "VipTrailBottom"

-- Destroys the VIP name tag and trail pieces on the character, if present.
local function removePerks(character: Model)
	local tag = character:FindFirstChild(TAG_NAME, true)
	if tag then
		tag:Destroy()
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, name in { TRAIL_NAME, ATTACH_TOP, ATTACH_BOTTOM } do
			local old = root:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
	end
end

-- Adds the VIP name tag and trail to the character. Idempotent: existing perks are removed first.
local function addPerks(character: Model)
	removePerks(character)

	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not root or not head:IsA("BasePart") or not root:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = TAG_NAME
	billboard.Adornee = head
	billboard.Size = UDim2.fromScale(4, 1.2)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "VIP"
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextColor3 = GOLD

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	label.Parent = billboard
	billboard.Parent = head

	local attachTop = Instance.new("Attachment")
	attachTop.Name = ATTACH_TOP
	attachTop.Position = Vector3.new(0, 0.8, 0)
	attachTop.Parent = root

	local attachBottom = Instance.new("Attachment")
	attachBottom.Name = ATTACH_BOTTOM
	attachBottom.Position = Vector3.new(0, -0.8, 0)
	attachBottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = attachTop
	trail.Attachment1 = attachBottom
	trail.Lifetime = 0.6
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = root

	if IS_STUDIO then
		print(("[VIP] perks on %s"):format(character.Name))
	end
end

-- Applies the perks if the player owns the VIP pass, otherwise removes them.
local function refresh(player: Player)
	local character = player.Character
	if not character then
		return
	end

	if PassService:Owns(player, "VIP") then
		addPerks(character)
	else
		removePerks(character)
	end
end

-- Waits for the character's parts to load, then applies the perks if the player owns the VIP pass.
local function onCharacterAdded(player: Player, character: Model)
	task.spawn(function()
		character:WaitForChild("Head", 10)
		character:WaitForChild("HumanoidRootPart", 10)

		if player.Character == character and PassService:Owns(player, "VIP") then
			addPerks(character)
		end
	end)
end

-- Connects the respawn handler for a player and handles the character they already have.
local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function VipService:Init() end

function VipService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	PassService.OwnershipChanged:Connect(function(player: Player, passKey: string, _owns: boolean)
		if passKey == "VIP" then
			refresh(player)
		end
	end)
end

return VipService
