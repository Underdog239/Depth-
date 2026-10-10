--!strict
-- Shared, static styling: no animation loop or external image assets.
local Theme = {
	background = Color3.fromRGB(14, 13, 11),
	panel = Color3.fromRGB(27, 24, 19),
	raised = Color3.fromRGB(42, 36, 27),
	edge = Color3.fromRGB(89, 71, 43),
	gold = Color3.fromRGB(226, 185, 99),
	lightGold = Color3.fromRGB(255, 226, 165),
	text = Color3.fromRGB(247, 239, 222),
	muted = Color3.fromRGB(190, 176, 151),
	ink = Color3.fromRGB(32, 24, 10),
}
function Theme.outline(object, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.edge; stroke.Thickness = thickness or 1
	stroke.Transparency = 0.25; stroke.Parent = object
end
function Theme.gradient(object, top, bottom)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom); gradient.Rotation = 90
	gradient.Parent = object
end
function Theme.primary(object)
	object.BackgroundColor3 = Color3.new(1,1,1); object.TextColor3 = Theme.ink
	object.Font = Enum.Font.GothamBold
	Theme.gradient(object, Theme.lightGold, Theme.gold)
end
return Theme
