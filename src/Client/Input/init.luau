--!strict
--[[ Input (init)

 Keyboard + gamepad -> GBA key mask. Bindings are fully remappable at runtime
 and can be saved/loaded, so the user can play like on real hardware.

 GBA key bits: 0 A, 1 B, 2 Select, 3 Start, 4 Right, 5 Left, 6 Up, 7 Down,
 8 R, 9 L (mirrors REG_KEYINPUT).
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local InputManager = {}
InputManager.__index = InputManager

function InputManager.new()
	local self = setmetatable({}, InputManager)
	self.keyboard = table.clone(Config.INPUT.defaultKeyboard)
	self.gamepad = table.clone(Config.INPUT.defaultGamepad)
	self.mask = 0
	self.enabled = true
	self.onKeyChanged = Signal.new()
	self._held = {} :: { [Enum.KeyCode]: number }
	self._connections = {}
	self._stick = { x = 0, y = 0 }
	self:_install()
	return self
end

function InputManager:_install()
	local UIS = game:GetService("UserInputService")
	table.insert(self._connections, UIS.InputBegan:Connect(function(input, processed)
		if processed or not self.enabled then return end
		self:_set(input.KeyCode, true)
	end))
	table.insert(self._connections, UIS.InputEnded:Connect(function(input)
		if not self.enabled then return end
		self:_set(input.KeyCode, false)
	end))
	table.insert(self._connections, UIS.WindowFocusReleased:Connect(function()
		self:clearAll()
	end))
end

function InputManager:_set(key: Enum.KeyCode, down: boolean)
	local bit = self.keyboard[key]
	if bit == nil then bit = self.gamepad[key] end
	if bit == nil then return end
	if down then
		self._held[key] = bit
	else
		self._held[key] = nil
	end
	self:recompute()
end

--- Rebuild the mask from held keys + analog stick state.
function InputManager:recompute()
	local mask = 0
	for _, bit in self._held do
		mask = bit32.bor(mask, bit32.lshift(1, bit))
	end
	local dz = Config.INPUT.stickDeadzone
	local s = self._stick
	if s.x > dz then mask = bit32.bor(mask, 0x10) end
	if s.x < -dz then mask = bit32.bor(mask, 0x20) end
	if s.y > dz then mask = bit32.bor(mask, 0x80) end
	if s.y < -dz then mask = bit32.bor(mask, 0x40) end
	self.mask = mask
	self.onKeyChanged:fire(mask)
end

function InputManager:clearAll()
	table.clear(self._held)
	self._stick = { x = 0, y = 0 }
	self:recompute()
end

--- Apply a normalised analog vector (x,y in [-1,1]) to the D-pad.
function InputManager:applyStick(x: number, y: number)
	self._stick = { x = x, y = y }
	self:recompute()
end

--- Read the primary thumbstick directly from UserInputService.
function InputManager:pollStick()
	local UIS = game:GetService("UserInputService")
	local ok, state = pcall(function()
		return UIS:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if not ok or not state then return end
	local x, y = 0, 0
	for _, obj in state do
		if obj.KeyCode == Enum.KeyCode.Thumbstick1 then
			x, y = obj.Position.X, obj.Position.Y
		end
	end
	self:applyStick(x, y)
end

--- Remap a key to a GBA button bit.
function InputManager:bind(key: Enum.KeyCode, bit: number)
	self.keyboard[key] = bit
end

function InputManager:unbind(key: Enum.KeyCode)
	self.keyboard[key] = nil
	self._held[key] = nil
	self:recompute()
end

function InputManager:exportBindings(): { [string]: number }
	local out = {}
	for key, bit in self.keyboard do
		out[key.Name] = bit
	end
	return out
end

function InputManager:importBindings(data: { [string]: number })
	for name, bit in data do
		local ok, key = pcall(function() return Enum.KeyCode[name] end)
		if ok then self.keyboard[key] = bit end
	end
end

function InputManager:destroy()
	for _, c in self._connections do c:Disconnect() end
	table.clear(self._connections)
	self.onKeyChanged:clear()
end

return InputManager
