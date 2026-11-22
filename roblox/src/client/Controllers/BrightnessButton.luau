--!strict
-- Round "☀" button that lives in the HUD's brightness slot (top right) and cycles the cave brightness level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.Lighting)
local Strings = require(Shared.Strings.Strings)
local LightingController = require(script.Parent.LightingController)

local BrightnessButton = {}

-- Nothing to set up. Must not yield.
function BrightnessButton:Init() end

-- Builds the button and its level label inside the HUD slot, then wires the tap handler.
function BrightnessButton:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- The HUD owns the slot and UIController builds it, so wait for it to appear.
	local slot = playerGui:WaitForChild("CrystalGroveUI"):WaitForChild("Hud"):WaitForChild("BrightnessSlot")
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetBrightness") :: RemoteEvent

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = UDim2.fromOffset(0, 0)
	button.Size = UDim2.fromScale(1, 1)
	button.Text = "☀"
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.fromRGB(255, 220, 120)
	button.BackgroundColor3 = Color3.fromRGB(20, 22, 40)
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 220, 120)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- Keeps the glyph off the circular edge.
	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingTop = UDim.new(0, 8)
	buttonPadding.PaddingBottom = UDim.new(0, 8)
	buttonPadding.PaddingLeft = UDim.new(0, 8)
	buttonPadding.PaddingRight = UDim.new(0, 8)
	buttonPadding.Parent = button

	button.Parent = slot

	local label = Instance.new("TextLabel")
	label.Name = "LevelLabel"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, 0, 1, 6)
	label.Size = UDim2.fromOffset(120, 28)
	label.ZIndex = 10
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 40)
	label.BackgroundTransparency = 0.25
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Visible = false

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 8)
	labelCorner.Parent = label

	local labelPadding = Instance.new("UIPadding")
	labelPadding.PaddingTop = UDim.new(0, 4)
	labelPadding.PaddingBottom = UDim.new(0, 4)
	labelPadding.PaddingLeft = UDim.new(0, 4)
	labelPadding.PaddingRight = UDim.new(0, 4)
	labelPadding.Parent = label

	label.Parent = slot

	-- Bumped on every tap so only the newest delay hides the label.
	local hideToken = 0

	button.Activated:Connect(function()
		local levels = LightingConfig.Levels
		local current = LightingController.current()
		local index = 0
		for i, level in levels do
			if level == current then
				index = i
				break
			end
		end

		local nextLevel = levels[index % #levels + 1]
		LightingController.applyFromTap(nextLevel)
		remote:FireServer(nextLevel)

		hideToken += 1
		local token = hideToken
		label.Text = Strings.get("Brightness." .. nextLevel)
		label.Visible = true
		task.delay(1.5, function()
			if token == hideToken then
				label.Visible = false
			end
		end)
	end)
end

return BrightnessButton
