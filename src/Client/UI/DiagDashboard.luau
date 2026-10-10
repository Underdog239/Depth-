--!strict
--[[ UI/DiagDashboard.luau

 The window that answers "what did the catcher find?" without the user running
 anything: it lists findings from the background diagnostics store, grouped by
 the four categories (error / bug / vulnerability / unfinished), shows how many
 times each fired, and prints the suggested fix.

 Open it any time; it refreshes live via Diag.onFinding.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local CATEGORY_COLORS = {
	error = Color3.fromRGB(220, 60, 60),
	bug = Color3.fromRGB(230, 150, 40),
	vulnerability = Color3.fromRGB(200, 60, 200),
	unfinished = Color3.fromRGB(90, 160, 230),
}

local Dashboard = {}
Dashboard.__index = Dashboard

function Dashboard.new(diag: any, parent: Instance?)
	local self = setmetatable({}, Dashboard)
	self.diag = diag
	self.filter = nil
	self.rows = {}
	self:_build(parent)
	self._conn = diag.onFinding:connect(function() self:refresh() end)
	self:refresh()
	return self
end

local function makeButton(text: string, parent: Instance, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.BackgroundColor3 = color or Color3.fromRGB(45, 48, 58)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.Parent = parent
	return b
end

function Dashboard:_build(parent: Instance?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "GBADiagDashboard"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 10
	gui.Parent = parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(560, 420)
	frame.Position = UDim2.new(0.5, -280, 0.5, -210)
	frame.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	self.frame = frame

	local title = Instance.new("TextLabel")
	title.Text = "GBA Diagnostics - background findings"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.new(1, 1, 1)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 0, 28)
	title.Position = UDim2.fromOffset(10, 8)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	local close = makeButton("Close", frame)
	close.Size = UDim2.fromOffset(60, 24)
	close.Position = UDim2.new(1, -70, 0, 8)
	close.MouseButton1Click:Connect(function() gui.Enabled = false end)

	local summary = Instance.new("TextLabel")
	summary.Name = "Summary"
	summary.Text = ""
	summary.Font = Enum.Font.Code
	summary.TextSize = 12
	summary.TextColor3 = Color3.fromRGB(180, 190, 210)
	summary.BackgroundTransparency = 1
	summary.Size = UDim2.new(1, -20, 0, 40)
	summary.Position = UDim2.fromOffset(10, 34)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.TextYAlignment = Enum.TextYAlignment.Top
	summary.Parent = frame
	self.summary = summary

	local buttons = Instance.new("Frame")
	buttons.Size = UDim2.new(1, -20, 0, 28)
	buttons.Position = UDim2.fromOffset(10, 76)
	buttons.BackgroundTransparency = 1
	buttons.Parent = frame

	local filters = { "all", "error", "bug", "vulnerability", "unfinished" }
	for i, name in filters do
		local b = makeButton(string.upper(name), buttons, CATEGORY_COLORS[name])
		b.Size = UDim2.fromOffset(96, 26)
		b.Position = UDim2.fromOffset((i - 1) * 100, 0)
		b.MouseButton1Click:Connect(function()
			self.filter = if name == "all" then nil else name
			self:refresh()
		end)
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -190)
	scroll.Position = UDim2.fromOffset(10, 110)
	scroll.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = frame
	self.scroll = scroll

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
end

function Dashboard:refresh()
	if not self.gui then return end
	local counts = self.diag.summary().counts
	self.summary.Text = string.format(
		"error: %d   bug: %d   vulnerability: %d   unfinished: %d\nscans run: %d",
		counts.error or 0, counts.bug or 0, counts.vulnerability or 0, counts.unfinished or 0,
		self.diag.summary().scanRuns or 0
	)

	for _, row in self.rows do row:Destroy() end
	table.clear(self.rows)

	local list = self.diag.findings({ category = self.filter })
	table.sort(list, function(a, b) return a.lastSeen > b.lastSeen end)
	for i, f in list do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -8, 0, 56)
		row.LayoutOrder = i
		row.Parent = self.scroll

		local tag = Instance.new("TextLabel")
		tag.Text = string.upper(f.category)
		tag.Font = Enum.Font.GothamBold
		tag.TextSize = 11
		tag.TextColor3 = CATEGORY_COLORS[f.category] or Color3.new(1, 1, 1)
		tag.BackgroundTransparency = 1
		tag.Size = UDim2.fromOffset(120, 16)
		tag.Position = UDim2.fromOffset(8, 4)
		tag.TextXAlignment = Enum.TextXAlignment.Left
		tag.Parent = row

		local msg = Instance.new("TextLabel")
		msg.Text = string.format("[x%d] %s", f.count, f.message)
		msg.Font = Enum.Font.Code
		msg.TextSize = 12
		msg.TextColor3 = Color3.fromRGB(220, 225, 235)
		msg.BackgroundTransparency = 1
		msg.Size = UDim2.new(1, -16, 0, 18)
		msg.Position = UDim2.fromOffset(8, 20)
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.TextTruncate = Enum.TextTruncate.AtEnd
		msg.Parent = row

		local fix = Instance.new("TextLabel")
		fix.Text = self.diag.advice(f)
		fix.Font = Enum.Font.Code
		fix.TextSize = 11
		fix.TextColor3 = Color3.fromRGB(140, 200, 150)
		fix.BackgroundTransparency = 1
		fix.Size = UDim2.new(1, -16, 0, 16)
		fix.Position = UDim2.fromOffset(8, 38)
		fix.TextXAlignment = Enum.TextXAlignment.Left
		fix.TextTruncate = Enum.TextTruncate.AtEnd
		fix.Parent = row

		table.insert(self.rows, row)
	end
end

function Dashboard:toggle()
	self.gui.Enabled = not self.gui.Enabled
	if self.gui.Enabled then self:refresh() end
end

function Dashboard:destroy()
	if self._conn then self._conn:disconnect() end
	if self.gui then self.gui:Destroy() end
end

return Dashboard
