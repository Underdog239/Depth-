--!strict
--[[ Emulator/GBA.luau

 Top-level console: owns the bus, CPU, PPU, DMA, timers, keypad and cartridge,
 and exposes the small surface the Roblox client actually needs.

   local gba = GBA.new({ rom = bytes })
   gba:setKeys(mask)
   local frame = gba:runFrame()   -- advances exactly one video frame
   local rgba = gba:framebuffer() -- 240*160*4 bytes
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MemoryBus = require(script.Parent.Bus.MemoryBus)
local Regions = require(script.Parent.Bus.Regions)
local Arm7tdmi = require(script.Parent.CPU.Arm7tdmi)
local Cartridge = require(script.Parent.Cart.Cartridge)
local HLEBIOS = require(script.Parent.Cart.HLEBIOS)
local Interrupts = require(script.Parent.Hardware.Interrupts)
local Timers = require(script.Parent.Hardware.Timers)
local Dma = require(script.Parent.Hardware.Dma)
local Keypad = require(script.Parent.Hardware.Keypad)
local Ppu = require(script.Parent.Hardware.Ppu)
local Apu = require(script.Parent.Hardware.Apu)

local GBA = {}
GBA.__index = GBA

function GBA.new(options: any)
	options = options or {}
	local self = setmetatable({}, GBA)

	self.bus = MemoryBus.new()
	self.interrupts = Interrupts.new()
	self.keypad = Keypad.new(self.interrupts)
	self.timers = Timers.new(self.interrupts)
	self.ppu = Ppu.new(self.bus, self.interrupts)
	self.dma = Dma.new(self.bus, self.interrupts)
	self.apu = Apu.new(self.interrupts)

	self.bus.interrupts = self.interrupts
	self.bus.keypad = self.keypad
	self.bus.timers = self.timers
	self.bus.ppu = self.ppu
	self.bus.dma = self.dma
	self.bus.sound = self.apu
	self.ppu.dma = self.dma

	self.cpu = Arm7tdmi.new(self.bus)
	self.cart = nil
	self.frames = 0
	self.diag = options.diag

	if options.bios then
		for i = 1, math.min(#options.bios, Regions.BIOS_SIZE) do
			self.bus.bios[i] = options.bios[i]
		end
	else
		self.bus.hleBios = HLEBIOS.new(self.bus)
	end

	if options.rom then
		self:loadROM(options.rom)
	end
	return self
end

--- Load a ROM image (byte array). Resets the machine to the entry point.
function GBA:loadROM(bytes: { number })
	self.cart = Cartridge.new(bytes)
	self.bus.cart = self.cart
	self:reset()
	return self.cart.info
end

function GBA:reset()
	self.interrupts:reset()
	self.timers:reset()
	self.dma:reset()
	self.keypad:reset()
	self.ppu:reset()
	self.apu:reset()
	-- Hardware always begins execution at the ROM base; the 4 bytes at ROM
	-- offset 0 are the entry-point branch instruction itself.
	self.cpu:reset(0x08000000)
	self.frames = 0
end

function GBA:setKeys(mask: number)
	self.keypad:setMask(mask)
end

function GBA:framebuffer(): { number }
	return self.ppu.framebuffer
end

function GBA:saveBytes(): { number }
	return self.cart and self.cart:saveBytes() or {}
end

function GBA:loadSaveBytes(bytes: { number })
	if self.cart then self.cart:loadSaveBytes(bytes) end
end

--- Run a single CPU instruction with proper cycle accounting.
function GBA:stepInstruction()
	if self.cpu.halted then
		local pending = bit32.band(self.interrupts.ie, self.interrupts.if_)
		if pending ~= 0 then
			self.cpu.halted = false
		else
			self.bus:tick(4)
			return
		end
	end
	local cycles = self.cpu:step()
	self.bus:tick(cycles + self.bus.stallCycles)
	self.bus.stallCycles = 0
end

--- Run until the PPU completes one frame (or the safety budget is exhausted).
function GBA:runFrame(): number
	self.ppu.frameComplete = false
	local guard = 0
	local maxIterations = Config.CORE.maxCyclesPerFrame
	while not self.ppu.frameComplete do
		self:stepInstruction()
		guard += 1
		if guard >= maxIterations then
			if self.diag then
				self.diag.report("frame budget exhausted before VBlank", {
					source = "GBA.runFrame", kind = "bug", severity = "warn",
					pc = self.cpu.regs[16],
				})
			end
			break
		end
	end
	self.frames += 1
	return self.ppu.frame
end

--- Run for a fixed number of master cycles (used by benchmarks/tests).
function GBA:runCycles(cycles: number)
	local start = self.bus.cycles
	while self.bus.cycles - start < cycles do
		self:stepInstruction()
	end
end

function GBA:info()
	return {
		rom = self.cart and self.cart.info or nil,
		frames = self.frames,
		instructions = self.cpu.instructions,
		cycles = self.bus.cycles,
		hleBios = self.bus.hleBios ~= nil,
	}
end

return GBA
