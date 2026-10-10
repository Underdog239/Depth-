--!strict
--[[ UI (init)

 The player-facing shell: a window with ROM loading (base64 paste), transport
 controls, scaling, state save/load and a button that opens the diagnostics
 dashboard. All emulator interaction goes through the `hooks` table so the UI
 stays decoupled from the core.

 hooks = {
   onLoadROM(bytes), onPlayPause(), onReset(), onScale(n),
   onSaveState(), onLoadState(), onToggleDiag(), onSetSpeed(n)
 }
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Base64 = require(ReplicatedStorage.Shared.Base64)
local Config = require(ReplicatedStorage.Shared.Config)

local UI = {}
UI.__index = UI

local function button(text: string, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.BackgroundColor3 = Color3.fromRGB(48, 52, 64)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = parent
	return b
end

function UI.new(hooks: any, parent: Instance?)
	local self = setmetatable({}, UI)
	self.hooks = hooks
	local player = game:GetService("Players").LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuauGBA"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent or player:WaitForChild("PlayerGui")
	self.gui = gui

	-- Screen host (the renderer parents its container here)
	local screenHost = Instance.new("Frame")
	screenHost.Name = "ScreenHost"
	screenHost.BackgroundColor3 = Color3.new(0, 0, 0)
	screenHost.BorderSizePixel = 0
	screenHost.Size = UDim2.fromOffset(Config.SCREEN_W * Config.RENDER.scale, Config.SCREEN_H * Config.RENDER.scale)
	screenHost.AnchorPoint = Vector2.new(0.5, 0.5)
	screenHost.Position = UDim2.new(0.5, 140, 0.5, 0)
	screenHost.Parent = gui
	self.screenHost = screenHost

	-- Control panel
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(320, 352)
	panel.Position = UDim2.new(0, 8, 0, 8)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 33)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui
	self.panel = panel

	local status = Instance.new("TextLabel")
	status.Text = "LuauGBA - load a ROM to begin"
	status.Font = Enum.Font.Code
	status.TextSize = 12
	status.TextColor3 = Color3.fromRGB(200, 210, 225)
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -12, 0, 40)
	status.Position = UDim2.fromOffset(6, 4)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextWrapped = true
	status.Parent = panel
	self.status = status

	-- ROM base64 box
	local box = Instance.new("TextBox")
	box.PlaceholderText = "paste base64 ROM here"
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Size = UDim2.new(1, -12, 0, 26)
	box.Position = UDim2.fromOffset(6, 46)
	box.Parent = panel
	self.romBox = box

	local loadBtn = button("Load ROM", panel)
	loadBtn.Size = UDim2.fromOffset(90, 24)
	loadBtn.Position = UDim2.fromOffset(6, 78)
	loadBtn.MouseButton1Click:Connect(function()
		local text = box.Text:gsub("%s", "")
		if #text < 8 then
			self:setStatus("ROM box is empty - paste base64 data first")
			return
		end
		if #text > 200000 then self:setStatus("Use an embedded ROM module for larger files"); return end
		local ok, bytes = pcall(Base64.decodeToBuffer, text)
		if ok and bytes and buffer.len(bytes) >= 0xC0 then
			self:setStatus(string.format("decoded %d bytes, loading...", buffer.len(bytes)))
			self.hooks.onLoadROM(bytes)
		else
			self:setStatus("failed to decode base64 ROM data")
		end
	end)

	local playBtn = button("Play", panel)
	playBtn.Size = UDim2.fromOffset(70, 24)
	playBtn.Position = UDim2.fromOffset(102, 78)
	self.playBtn = playBtn
	playBtn.MouseButton1Click:Connect(function()
		local running = self.hooks.onPlayPause()
		playBtn.Text = running and "Pause" or "Play"
	end)

	local resetBtn = button("Reset", panel)
	resetBtn.Size = UDim2.fromOffset(70, 24)
	resetBtn.Position = UDim2.fromOffset(178, 78)
	resetBtn.MouseButton1Click:Connect(function() self.hooks.onReset() end)

	local diagBtn = button("Diagnostics", panel)
	diagBtn.Size = UDim2.fromOffset(100, 24)
	diagBtn.Position = UDim2.fromOffset(6, 108)
	diagBtn.MouseButton1Click:Connect(function() self.hooks.onToggleDiag() end)

	local saveBtn = button("Save state", panel)
	saveBtn.Size = UDim2.fromOffset(80, 24)
	saveBtn.Position = UDim2.fromOffset(112, 108)
	saveBtn.MouseButton1Click:Connect(function() self.hooks.onSaveState() end)

	local loadStateBtn = button("Load state", panel)
	loadStateBtn.Size = UDim2.fromOffset(80, 24)
	loadStateBtn.Position = UDim2.fromOffset(198, 108)
	loadStateBtn.MouseButton1Click:Connect(function() self.hooks.onLoadState() end)

	local demo = button("Run demo", panel)
	demo.Size = UDim2.fromOffset(100, 24)
	demo.Position = UDim2.fromOffset(6, 138)
	demo.MouseButton1Click:Connect(function() self.hooks.onDemo() end)

	local saveBox = Instance.new("TextBox")
	saveBox.Text = ""
	saveBox.PlaceholderText = "Battery save data: paste to import, or export and copy"
	saveBox.ClearTextOnFocus = false
	saveBox.MultiLine = true
	saveBox.TextWrapped = true
	saveBox.TextSize = 12
	saveBox.Font = Enum.Font.Code
	saveBox.TextColor3 = Color3.new(1, 1, 1)
	saveBox.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	saveBox.Size = UDim2.new(1, -12, 0, 48)
	saveBox.Position = UDim2.fromOffset(6, 170)
	saveBox.Parent = panel
	local export = button("Export save", panel)
	export.Size = UDim2.fromOffset(110, 24)
	export.Position = UDim2.fromOffset(6, 226)
	export.MouseButton1Click:Connect(function()
		local text = self.hooks.onExportSave()
		if text then
			saveBox.Text = text
			saveBox:CaptureFocus()
			saveBox.CursorPosition = #text + 1
			saveBox.SelectionStart = 1
		end
	end)
	local import = button("Import save", panel)
	import.Size = UDim2.fromOffset(110, 24)
	import.Position = UDim2.fromOffset(122, 226)
	import.MouseButton1Click:Connect(function()
		if #saveBox.Text > 180000 then self:setStatus("Save text is too large"); return end
		self.hooks.onImportSave(saveBox.Text)
	end)

	local help = Instance.new("TextLabel")
	help.BackgroundTransparency = 1
	help.TextColor3 = Color3.fromRGB(200, 210, 225)
	help.Font = Enum.Font.Code
	help.TextSize = 12
	help.TextWrapped = true
	help.Text = "Z/X: A/B · arrows: move · Enter: Start\nA/C: L/R · RightShift: Select\nDemo: hold a button to change colour. Audio is silent."
	help.Size = UDim2.new(1, -12, 0, 54)
	help.Position = UDim2.fromOffset(6, 256)
	help.Parent = panel
	local metrics = help:Clone()
	metrics.Text = "Ready for a ROM or the built-in demo"
	metrics.Size = UDim2.new(1, -12, 0, 36)
	metrics.Position = UDim2.fromOffset(6, 312)
	metrics.Parent = panel
	self.metrics = metrics

	return self
end

function UI:setStatus(text: string)
	self.status.Text = text
end

function UI:setRunning(running: boolean)
	self.playBtn.Text = running and "Pause" or "Play"
end

function UI:setMetrics(text: string)
	self.metrics.Text = text
end

function UI:setScale(scale: number)
	self.screenHost.Size = UDim2.fromOffset(Config.SCREEN_W * scale, Config.SCREEN_H * scale)
end

function UI:destroy()
	self.gui:Destroy()
end

return UI
