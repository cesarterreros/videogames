--!strict
-- Components.luau - factory for the plain-Instance client UI: buttons, labels, panels and progress bars.
-- Builds raw Instances (no UI library), sets Parent last on every object it creates and returns it.
-- No remotes and no Strings lookups: callers pass finished text. Every text object uses Theme.fontFace().

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Components = {}

-- Press feedback tuning: a quick squish while the pointer is held down.
local PRESS_SCALE = 0.95
local PRESS_TIME = 0.08

-- Called once by UIController; every successful button press calls it (plays the Click sound). nil = silent.
local clickSound: (() -> ())? = nil

export type ButtonProps = {
	Text: string?,
	Icon: string?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: string?,
	TextColor: string?,
	OnClick: () -> (),
	Parent: Instance,
	Name: string?,
	LayoutOrder: number?,
	TextSize: number?, -- largest text size; text still shrinks to fit (default 28)
}

export type LabelProps = {
	Text: string,
	TextSize: number?,
	Color: string?,
	Parent: Instance,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Name: string?,
	LayoutOrder: number?,
	XAlignment: Enum.TextXAlignment?,
}

export type PanelProps = {
	Title: string,
	Size: UDim2,
	Parent: Instance,
	OnClose: () -> (),
	Name: string?,
	AspectRatio: number?,
}

export type ProgressBarProps = {
	Parent: Instance,
	Size: UDim2,
	Position: UDim2?,
	Name: string?,
	LayoutOrder: number?,
}

export type ProgressBar = {
	Root: Frame,
	Set: (fraction: number, text: string) -> (),
}

-- Applies the optional positioning props shared by every component.
local function applyLayout(guiObject: GuiObject, position: UDim2?, anchorPoint: Vector2?, layoutOrder: number?)
	if position then
		guiObject.Position = position
	end
	if anchorPoint then
		guiObject.AnchorPoint = anchorPoint
	end
	if layoutOrder ~= nil then
		guiObject.LayoutOrder = layoutOrder
	end
end

-- Reads the "Disabled" attribute; a button with no attribute counts as enabled.
local function readEnabled(button: GuiButton): boolean
	return button:GetAttribute("Disabled") ~= true
end

-- TextButton and TextBox are the only GuiObjects with a TextTransparency property.
local function setTextTransparency(button: GuiButton, value: number)
	if button:IsA("TextButton") then
		button.TextTransparency = value
	elseif button:IsA("TextBox") then
		button.TextTransparency = value
	end
end

-- "Icon Text" when both are given, otherwise whichever one exists, otherwise "".
local function buttonText(icon: string?, text: string?): string
	local iconText = icon or ""
	local labelText = text or ""
	if #iconText > 0 and #labelText > 0 then
		return iconText .. " " .. labelText
	end
	if #iconText > 0 then
		return iconText
	end
	return labelText
end

-- Sets the function called on every button press (the Click sound). nil makes presses silent.
function Components.setClickSound(fn: (() -> ())?)
	clickSound = fn
end

-- Builds a chunky rounded button with press feedback and a click-sound hook.
function Components.button(props: ButtonProps): TextButton
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.Size = props.Size
	applyLayout(button, props.Position, props.AnchorPoint, props.LayoutOrder)

	button.Text = buttonText(props.Icon, props.Text)
	button.FontFace = Theme.fontFace()
	button.TextScaled = true
	button.AutoButtonColor = false
	button.TextColor3 = Theme.color(props.TextColor or Theme.Colors.Text)

	-- Remembered so setEnabled can put the original colour back.
	local normalColor = props.Color or Theme.Colors.PanelLight
	button.BackgroundColor3 = Theme.color(normalColor)
	button:SetAttribute("NormalColor", normalColor)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Corner)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.StrokeThickness
	stroke.Color = Theme.color(Theme.Colors.Stroke)
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = button

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = 10
	textSize.MaxTextSize = props.TextSize or 28
	textSize.Parent = button

	local touchSize = Instance.new("UISizeConstraint")
	touchSize.MinSize = Vector2.new(Theme.MinTouch, Theme.MinTouch)
	touchSize.Parent = button

	local pressScale = Instance.new("UIScale")
	pressScale.Name = "PressScale"
	pressScale.Parent = button

	-- Squish on press, spring back on release or when the pointer slides off.
	local function tweenScale(target: number)
		TweenService:Create(pressScale, TweenInfo.new(PRESS_TIME), { Scale = target }):Play()
	end
	button.MouseButton1Down:Connect(function()
		tweenScale(PRESS_SCALE)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(1)
	end)
	button.MouseLeave:Connect(function()
		tweenScale(1)
	end)

	button.Activated:Connect(function()
		if not readEnabled(button) then
			return
		end
		if clickSound then
			pcall(clickSound)
		end
		props.OnClick()
	end)

	button.Parent = props.Parent
	return button
end

-- Greys a button out and makes it ignore taps, or restores it.
function Components.setEnabled(button: GuiButton, enabled: boolean)
	button:SetAttribute("Disabled", not enabled)
	if enabled then
		local stored = button:GetAttribute("NormalColor")
		if type(stored) ~= "string" then
			stored = Theme.Colors.PanelLight
		end
		button.BackgroundColor3 = Theme.color(stored :: string)
		setTextTransparency(button, 0)
	else
		button.BackgroundColor3 = Theme.color(Theme.Colors.Disabled)
		setTextTransparency(button, 0.4)
	end
end

-- True unless the button carries the "Disabled" attribute.
function Components.isEnabled(button: GuiButton): boolean
	return readEnabled(button)
end

-- Builds an outlined text label; TextScaled with a cap unless an explicit TextSize is given.
function Components.label(props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size
	applyLayout(label, props.Position, props.AnchorPoint, props.LayoutOrder)

	label.Text = props.Text
	label.FontFace = Theme.fontFace()
	label.TextColor3 = Theme.color(props.Color or Theme.Colors.Text)
	label.TextXAlignment = props.XAlignment or Enum.TextXAlignment.Center
	label.TextWrapped = true
	label.BackgroundTransparency = 1

	if props.TextSize then
		label.TextSize = props.TextSize
		label.TextScaled = false
	else
		label.TextScaled = true
		local textSize = Instance.new("UITextSizeConstraint")
		textSize.MaxTextSize = 32
		textSize.Parent = label
	end

	-- Contextual stroke outlines the glyphs, which keeps text readable on any background.
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 1.5
	stroke.Color = Theme.color(Theme.Colors.Stroke)
	stroke.Parent = label

	label.Parent = props.Parent
	return label
end

-- Builds a modal-style panel with a title and a close button; returns (root, content).
function Components.panel(props: PanelProps): (Frame, Frame)
	local root = Instance.new("Frame")
	root.Name = props.Name or "Panel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = props.Size
	root.BackgroundColor3 = Theme.color(Theme.Colors.Panel)
	root.Visible = false
	root.Active = true -- taps on the panel must not fall through to the cave behind it

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Corner)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = Theme.color(Theme.Colors.Stroke)
	stroke.Parent = root

	if props.AspectRatio then
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = props.AspectRatio
		aspect.Parent = root
	end

	Components.label({
		Name = "Title",
		Text = props.Title,
		Size = UDim2.new(1, -64, 0, 48),
		Position = UDim2.new(0, 12, 0, 0),
		Color = Theme.Colors.Gold,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})

	Components.button({
		Name = "Close",
		Text = Theme.Icons.Close,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Color = Theme.Colors.Bad,
		OnClick = props.OnClose,
		Parent = root,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, 12, 0, 56)
	content.Size = UDim2.new(1, -24, 1, -68)
	content.ClipsDescendants = true
	content.Parent = root

	root.Parent = props.Parent
	return root, content
end

-- Builds a pill-shaped progress bar with a centred text overlay; returns { Root, Set }.
function Components.progressBar(props: ProgressBarProps): ProgressBar
	local root = Instance.new("Frame")
	root.Name = props.Name or "ProgressBar"
	root.Size = props.Size
	applyLayout(root, props.Position, nil, props.LayoutOrder)
	root.BackgroundColor3 = Theme.color(Theme.Colors.Bg)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = Theme.color(Theme.Colors.Stroke)
	stroke.Parent = root

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Theme.color(Theme.Colors.Good)
	fill.Size = UDim2.fromScale(0, 1)

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	fill.Parent = root

	local text = Components.label({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		Parent = root,
	})

	-- fraction is clamped to 0..1; NaN collapses to an empty bar.
	local function set(fraction: number, labelText: string)
		local value = fraction
		if value ~= value then
			value = 0
		end
		value = math.clamp(value, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		text.Text = labelText
	end
	set(0, "")

	root.Parent = props.Parent
	return { Root = root, Set = set }
end

return Components
