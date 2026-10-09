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
	screenHost.Position = UDim2.new(0.5, -(Config.SCREEN_W * Config.RENDER.scale) // 2, 0.5, -(Config.SCREEN_H * Config.RENDER.scale) // 2)
	screenHost.Parent = gui
	self.screenHost = screenHost

	-- Control panel
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(300, 150)
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
		local ok, bytes = pcall(Base64.decode, text)
		if ok and bytes and #bytes > 0 then
			self:setStatus(string.format("decoded %d bytes, loading...", #bytes))
			self.hooks.onLoadROM(bytes)
		else
			self:setStatus("failed to decode base64 ROM data")
		end
	end)

	local playBtn = button("Pause", panel)
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

	return self
end

function UI:setStatus(text: string)
	self.status.Text = text
end

function UI:destroy()
	self.gui:Destroy()
end

return UI
