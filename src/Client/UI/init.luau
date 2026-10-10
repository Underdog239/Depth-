--!strict
-- Responsive shell. All emulator operations cross the hooks table.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Base64 = require(ReplicatedStorage.Shared.Base64)
local Config = require(ReplicatedStorage.Shared.Config)
local UIS = game:GetService("UserInputService")
local Layout = require(script.Layout)
local UI = {}
UI.__index = UI
local foreground = Color3.fromRGB(224, 233, 245)
local accent = Color3.fromRGB(79, 208, 170)
local function round(object, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10); corner.Parent = object
end
local function label(text, parent, height)
	local object = Instance.new("TextLabel")
	object.Text = text; object.Font = Enum.Font.Gotham; object.TextSize = 14
	object.TextColor3 = foreground; object.BackgroundTransparency = 1
	object.TextWrapped = true; object.TextXAlignment = Enum.TextXAlignment.Left
	object.Size = UDim2.new(1, 0, 0, height or 44); object.Parent = parent
	return object
end
local function button(text, parent, fn)
	local object = Instance.new("TextButton")
	object.Text = text; object.Font = Enum.Font.GothamMedium; object.TextSize = 14
	object.TextColor3 = foreground; object.BackgroundColor3 = Color3.fromRGB(39, 51, 68)
	object.BorderSizePixel = 0; object.Size = UDim2.new(1, 0, 0, 44)
	object.AutoButtonColor = true; object.Parent = parent; round(object)
	if fn then object.Activated:Connect(fn) end
	return object
end
local function box(placeholder, parent)
	local object = Instance.new("TextBox")
	object.PlaceholderText = placeholder; object.Text = ""; object.ClearTextOnFocus = false
	object.Font = Enum.Font.Code; object.TextSize = 13; object.TextColor3 = foreground
	object.TextWrapped = true; object.MultiLine = true
	object.BackgroundColor3 = Color3.fromRGB(12, 18, 28); object.BorderSizePixel = 0
	object.Size = UDim2.new(1, 0, 0, 70); object.Parent = parent; round(object)
	return object
end
function UI.new(hooks, parent)
	local self = setmetatable({hooks = hooks, connections = {}, open = true, touchOverride = nil}, UI)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuauGBA"; gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1); root.BackgroundColor3 = Color3.fromRGB(10, 15, 24)
	root.BorderSizePixel = 0; root.Parent = gui; self.root = root
	local title = label("DEPTH  /  handheld", root, 40)
	title.Font = Enum.Font.GothamBold; title.TextSize = 20
	title.Position = UDim2.fromOffset(16, 0); title.Size = UDim2.new(1, -112, 0, 40)
	local menuButton = button("Menu", root, function() self:showMenu(not self.open) end)
	menuButton.Size = UDim2.fromOffset(80, 40); menuButton.Position = UDim2.new(1, -92, 0, 0)
	local status = label("Choose Run demo or add a ROM from the menu", root, 46)
	status.Position = UDim2.fromOffset(16, 44); status.Size = UDim2.new(1, -32, 0, 46)
	self.status = status
	local screen = Instance.new("Frame")
	screen.Name = "ScreenHost"; screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BorderSizePixel = 0; screen.AnchorPoint = Vector2.new(0.5, 0)
	screen.Parent = root; self.screenHost = screen
	local metrics = label("", root, 28)
	metrics.TextSize = 11; metrics.TextXAlignment = Enum.TextXAlignment.Center
	metrics.Position = UDim2.new(0, 8, 1, -28); metrics.Size = UDim2.new(1, -16, 0, 28)
	self.metrics = metrics

	local touch = Instance.new("Frame")
	touch.Name = "TouchControls"; touch.Size = UDim2.new(1, -24, 0, 160)
	touch.Position = UDim2.new(0, 12, 1, -192); touch.BackgroundTransparency = 1; touch.Parent = root
	self.touchControls = touch
	local keys = {{"↑",6,48,0,false},{"←",5,0,48,false},{"↓",7,48,96,false},{"→",4,96,48,false},
		{"L",9,0,0,false},{"R",8,0,0,true},{"Select",2,48,0,true},{"Start",3,96,0,true},
		{"B",1,48,96,true},{"A",0,96,48,true}}
	for _, spec in keys do
		local b = button(spec[1], touch)
		b.TextSize = spec[1] == "Select" and 10 or 13
		b.Size = UDim2.fromOffset(44,44)
		b.Position = spec[5] and UDim2.new(1, -140 + spec[3], 0, spec[4]) or UDim2.fromOffset(spec[3],spec[4])
		b.InputBegan:Connect(function(event)
			if event.UserInputType == Enum.UserInputType.Touch or event.UserInputType == Enum.UserInputType.MouseButton1 then
				hooks.onTouch(event, spec[2], true)
			end
		end)
	end
	table.insert(self.connections, UIS.InputEnded:Connect(function(event) hooks.onTouch(event, nil, false) end))

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "Menu"; panel.BackgroundColor3 = Color3.fromRGB(20, 28, 41)
	panel.BorderSizePixel = 0; panel.AnchorPoint = Vector2.new(0.5,0)
	panel.Position = UDim2.new(0.5,0,0,94); panel.ZIndex = 3
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y; panel.CanvasSize = UDim2.new()
	panel.ScrollBarThickness = 4; panel.Parent = root; self.panel = panel; round(panel,14)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0,14); padding.PaddingRight = UDim.new(0,14)
	padding.PaddingTop = UDim.new(0,12); padding.PaddingBottom = UDim.new(0,14); padding.Parent = panel
	local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0,8)
	list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel
	local order = 0
	local function item(object) order += 1; object.LayoutOrder = order; return object end
	local function text(content, height) return item(label(content, panel, height)) end
	local function action(content, fn) return item(button(content, panel, fn)) end
	local function pair(left, right, first, second)
		local row = Instance.new("Frame"); row.BackgroundTransparency = 1
		row.Size = UDim2.new(1,0,0,44); row.Parent = panel; item(row)
		local a,b = button(left,row,first),button(right,row,second)
		a.Size = UDim2.new(0.5,-4,1,0); b.Size = a.Size; b.Position = UDim2.new(0.5,4,0,0)
		return a,b
	end
	text("YOUR POCKET CONSOLE",28).TextColor3 = accent
	self.deviceLabel = text("",38)
	self.demoBtn = action("Run demo  •  no ROM needed",function() hooks.onDemo(); self:showMenu(false) end)
	self.demoBtn.BackgroundColor3 = Color3.fromRGB(28,104,86)
	self.playBtn = pair("Play", "Reset",function()
		local active = hooks.onPlayPause(); self:setRunning(active)
		if active then self:showMenu(false) end
	end,function() hooks.onReset() end)
	pair("Save state","Load state",function() hooks.onSaveState() end,function() hooks.onLoadState() end)
	text("ADD A GAME",28).TextColor3 = accent
	text("Download the ROM helper HTML from the GitHub link below and open it in a browser. Choose a .gba, Generate, then copy small-ROM base64 here. Larger ROMs: use its Studio installer.",104)
	local helper = item(box("ROM helper location",panel)); helper.Text = Config.ROM_HELP_URL
	helper.MultiLine = false; helper.Size = UDim2.new(1,0,0,44)
	self.romBox = item(box("Paste small ROM base64 here (up to 200,000 characters)",panel))
	action("Load pasted ROM",function()
		local data = self.romBox.Text
		if #data > 200000 then self:setStatus("ROM too large for paste. Use the helper's Studio installer."); return end
		local ok, bytes = pcall(Base64.decodeToBuffer,data)
		if not ok or buffer.len(bytes) < 0xC0 then self:setStatus("Invalid ROM text. Copy base64 from the ROM helper."); return end
		if hooks.onLoadROM(bytes) then self.romBox.Text = ""; self:showMenu(false) end
	end)
	text("CONTROLS",28).TextColor3 = accent
	text("Touch buttons appear on phones/tablets. Keyboard: arrows + Z/X. Controller: D-pad/stick + A/B, shoulders, Start/Select. Y opens this menu.",78)
	local touchButton
	touchButton = action("Touch controls: Auto",function()
		if self.touchOverride == nil then self.touchOverride = true
		elseif self.touchOverride then self.touchOverride = false else self.touchOverride = nil end
		touchButton.Text = "Touch controls: " .. (self.touchOverride == nil and "Auto" or (self.touchOverride and "On" or "Off"))
		self:layout()
	end)
	text("Remap: select an action, then press a keyboard or controller button. Escape/Y cancels. Mappings last this session.",64)
	self.bindingButtons = {}
	for bit, name in {"A","B","Select","Start","Right","Left","Up","Down","R","L"} do
		local b
		b = action(name .. "  •  change binding",function()
			self:setStatus("Press a key or controller button for " .. name)
			hooks.onRemap(bit-1,function(message) self:setStatus(message); self:updateBindings() end)
		end)
		self.bindingButtons[bit] = {button=b,name=name}
	end
	action("Restore default controls",function() hooks.onResetBindings(); self:updateBindings() end)
	text("PERFORMANCE & AUDIO",28).TextColor3 = accent
	local battery = false
	local power
	power = action("Performance: Balanced (automatic)",function()
		battery = not battery; hooks.onLowPower(battery)
		power.Text = battery and "Performance: Battery saver" or "Performance: Balanced (automatic)"
	end)
	text("Work is spread across frames to keep controls responsive. Demanding games may run slowly. Battery saver reduces CPU work further.",66)
	self.audioLabel = text("",64)
	local muted = false
	local mute
	mute = action("Mute audio",function() muted = not muted; hooks.onMute(muted); mute.Text = muted and "Unmute audio" or "Mute audio" end)
	self.audioBox = item(box("Optional Roblox square-wave audio asset ID",panel))
	pair("Set audio asset", "Test tone",function() self:setStatus(hooks.onAudioAsset(self.audioBox.Text)) end,
		function() self:setStatus(hooks.onTestTone()) end)
	text("The optional asset adapter approximates square tones. Full PCM game music is unavailable through public Roblox client APIs. See docs/AUDIO.md.",84)
	text("SAVES & HEALTH",28).TextColor3 = accent
	text("Export your battery save before leaving. Paste it back after loading the same game. State snapshots stay in this session.",66)
	self.saveBox = item(box("Battery save text",panel))
	pair("Export save","Import save",function()
		local value = hooks.onExportSave()
		if value then self.saveBox.Text = value; self.saveBox:CaptureFocus(); self.saveBox.CursorPosition = #value+1; self.saveBox.SelectionStart = 1 end
	end,function()
		if #self.saveBox.Text > 180000 then self:setStatus("Save text is too large"); return end
		hooks.onImportSave(self.saveBox.Text)
	end)
	action("Health report & background scans",function() hooks.onToggleDiag() end)
	text("Live checks report errors and apply performance/input recovery. Source findings come from this build's scan. GitHub Actions publishes fresh reports after pushes.",90)
	local github = item(box("GitHub reports",panel)); github.Text = Config.REPORT_URL; github.Size = UDim2.new(1,0,0,44)
	action("Back to game",function() self:showMenu(false) end)
	table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:layout() end))
	table.insert(self.connections, UIS.LastInputTypeChanged:Connect(function() self:layout() end))
	self:layout()
	return self
end
function UI:updateBindings()
	for bit, row in self.bindingButtons do row.button.Text = row.name .. "  •  " .. self.hooks.describeBinding(bit-1) end
end
function UI:layout()
	local size = self.root.AbsoluteSize
	local width,height = math.max(size.X,280),math.max(size.Y,240)
	local last = UIS:GetLastInputType()
	local controller = string.find(last.Name,"Gamepad",1,true) ~= nil
	local autoTouch = UIS.TouchEnabled and (last == Enum.UserInputType.Touch or (not UIS.KeyboardEnabled and not controller))
	local touch = self.touchOverride
	if touch == nil then touch = autoTouch end
	self.touchControls.Visible = touch and not self.open
	self.deviceLabel.Text = (controller and "Controller" or (autoTouch and "Phone / tablet" or "Keyboard / mouse")) .. " detected · " .. Config.VERSION
	local geometry = Layout.compute(width,height,touch)
	self.screenHost.Size = UDim2.fromOffset(geometry.screenWidth,geometry.screenHeight)
	self.screenHost.Position = UDim2.new(0.5,0,0,geometry.screenY)
	self.panel.Size = UDim2.fromOffset(geometry.menuWidth,geometry.menuHeight)
end
function UI:showMenu(open)
	self.open = open; self.panel.Visible = open
	self.hooks.onMenuChange(open)
	game:GetService("GuiService").SelectedObject = open and self.demoBtn or nil
	self:layout()
end
function UI:setStatus(text) self.status.Text = text end
function UI:setRunning(running) self.playBtn.Text = running and "Pause" or "Play" end
function UI:setMetrics(text) self.metrics.Text = text end
function UI:setAudioStatus(text) self.audioLabel.Text = text end
function UI:setScale(_scale) self:layout() end
function UI:destroy()
	for _,conn in self.connections do conn:Disconnect() end
	self.gui:Destroy()
end
return UI
