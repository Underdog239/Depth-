--!strict
--[[ Emulator/Bus/MemoryBus.luau

 The system bus. Owns every memory array and routes CPU accesses to the right
 region or hardware component. Also tracks the cycle counter that drives the
 PPU, timers and DMA.

 Design notes:
   * reads/writes are plain functions with a single top-byte branch, tuned for
     the interpreter hot path;
   * unmapped regions return the last value driven on the bus (open bus), which
     a handful of games actually rely on;
   * VRAM ignores 8-bit writes and ROM ignores all writes, per hardware.
 ]]

local Regions = require(script.Parent.Regions)

local MemoryBus = {}
MemoryBus.__index = MemoryBus

function MemoryBus.new()
	local bus = {
		bios = table.create(Regions.BIOS_SIZE, 0),
		ewram = table.create(Regions.EWRAM_SIZE, 0),
		iwram = table.create(Regions.IWRAM_SIZE, 0),
		pal = table.create(Regions.PAL_SIZE, 0),
		vram = table.create(Regions.VRAM_SIZE, 0),
		oam = table.create(Regions.OAM_SIZE, 0),
		io = table.create(0x400, 0),
		cycles = 0,
		stallCycles = 0,
		openBus = 0,
		-- components (assigned by GBA.luau)
		ppu = nil, dma = nil, timers = nil, keypad = nil, interrupts = nil, cart = nil,
		-- waitstates (simplified): extra cycles per access region
		ws = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	}
	return setmetatable(bus, MemoryBus) :: any
end

function MemoryBus:addCycles(n: number)
	self.stallCycles += n
end

--- Advance every timed component by `n` master cycles.
function MemoryBus:tick(n: number)
	if n <= 0 then return end
	self.cycles += n
	if self.ppu then self.ppu:tick(n) end
	if self.timers then self.timers:tick(n) end
	-- audio (APU) would be advanced here too
end

-- Reads ---------------------------------------------------------------------

function MemoryBus:read8(addr: number): number
	local top = addr // 0x1000000
	if top <= 0x01 then
		return self.bios[bit32.band(addr, Regions.BIOS_MASK) + 1] or 0
	elseif top == 0x02 then
		return self.ewram[bit32.band(addr, Regions.EWRAM_MASK) + 1] or 0
	elseif top == 0x03 then
		return self.iwram[bit32.band(addr, Regions.IWRAM_MASK) + 1] or 0
	elseif top == 0x04 then
		return bit32.band(self:readIO16(bit32.band(addr, 0x3FE)), 0xFF)
	elseif top == 0x05 then
		return self.pal[bit32.band(addr, Regions.PAL_MASK) + 1] or 0
	elseif top == 0x06 then
		return self.vram[bit32.band(addr, Regions.VRAM_MASK) + 1] or 0
	elseif top == 0x07 then
		return self.oam[bit32.band(addr, Regions.OAM_MASK) + 1] or 0
	elseif top <= 0x0D then
		return self.cart and self.cart:read8(bit32.band(addr, 0x1FFFFFF)) or 0
	else
		-- SRAM/Flash, 8-bit only (mirrored every 64 KiB)
		return self.cart and (self.cart:saveBytes()[bit32.band(addr, 0xFFFF) + 1] or 0) or 0
	end
end

function MemoryBus:read16(addr: number): number
	local top = addr // 0x1000000
	if top == 0x04 then return self:readIO16(bit32.band(addr, 0x3FE)) end
	local a0 = self:read8(addr)
	local a1 = self:read8(addr + 1)
	return a0 + a1 * 0x100
end

function MemoryBus:read32(addr: number): number
	local top = addr // 0x1000000
	if top == 0x04 then
		-- Most IO registers are 16-bit; upper half reads as zero on the GBA.
		return self:readIO16(bit32.band(addr, 0x3FE))
	end
	local a0 = self:read8(addr)
	local a1 = self:read8(addr + 1)
	local a2 = self:read8(addr + 2)
	local a3 = self:read8(addr + 3)
	return a0 + a1 * 0x100 + a2 * 0x10000 + a3 * 0x1000000
end

-- Writes --------------------------------------------------------------------

function MemoryBus:write8(addr: number, value: number)
	local top = addr // 0x1000000
	value = bit32.band(value, 0xFF)
	if top <= 0x01 then
		return -- BIOS is read-only
	elseif top == 0x02 then
		self.ewram[bit32.band(addr, Regions.EWRAM_MASK) + 1] = value
	elseif top == 0x03 then
		self.iwram[bit32.band(addr, Regions.IWRAM_MASK) + 1] = value
	elseif top == 0x04 then
		local off = bit32.band(addr, 0x3FE)
		local cur = self:readIO16(off)
		if addr % 2 == 0 then
			self:writeIO16(off, bit32.bor(bit32.band(cur, 0xFF00), value))
		else
			self:writeIO16(off, bit32.bor(bit32.band(cur, 0x00FF), bit32.lshift(value, 8)))
		end
	elseif top == 0x05 then
		self.pal[bit32.band(addr, Regions.PAL_MASK) + 1] = value
	elseif top == 0x06 then
		-- 8-bit writes to VRAM are ignored on real hardware
		return
	elseif top == 0x07 then
		self.oam[bit32.band(addr, Regions.OAM_MASK) + 1] = value
	elseif top <= 0x0D then
		return -- ROM read-only
	else
		if self.cart then
			self.cart:saveBytes()[bit32.band(addr, 0xFFFF) + 1] = value
		end
	end
end

function MemoryBus:write16(addr: number, value: number)
	local top = addr // 0x1000000
	if top == 0x04 then return self:writeIO16(bit32.band(addr, 0x3FE), value) end
	if top == 0x06 then
		-- VRAM: only aligned 16-bit writes land
		local off = bit32.band(addr, Regions.VRAM_MASK)
		self.vram[off + 1] = bit32.band(value, 0xFF)
		self.vram[off + 2] = bit32.band(value // 0x100, 0xFF)
		return
	end
	self:write8(addr, bit32.band(value, 0xFF))
	self:write8(addr + 1, bit32.band(value // 0x100, 0xFF))
end

function MemoryBus:write32(addr: number, value: number)
	local top = addr // 0x1000000
	if top == 0x04 then
		self:writeIO16(bit32.band(addr, 0x3FE), bit32.band(value, 0xFFFF))
		return
	end
	if top == 0x06 then
		self:write16(addr, bit32.band(value, 0xFFFF))
		self:write16(addr + 2, bit32.band(value // 0x10000, 0xFFFF))
		return
	end
	self:write16(addr, bit32.band(value, 0xFFFF))
	self:write16(addr + 2, bit32.band(value // 0x10000, 0xFFFF))
end

-- IO routing ----------------------------------------------------------------

function MemoryBus:readIO16(off: number): number
	off = bit32.band(off, 0x3FE)
	if off <= 0x056 then
		if self.ppu then return self.ppu:read16(off) end
		return 0
	elseif off >= 0x060 and off <= 0x0A8 then
		if self.sound then return self.sound:read16(off) end
		return 0
	elseif off >= 0x0B0 and off <= 0x0DF then
		if self.dma then return self.dma:read16(off) end
		return 0
	elseif off >= 0x100 and off <= 0x10F then
		if self.timers then return self.timers:read16(off) end
		return 0
	elseif off >= 0x130 and off <= 0x132 then
		if self.keypad then return self.keypad:read16(off) end
		return 0
	elseif off >= 0x200 and off <= 0x208 then
		if self.interrupts then return self.interrupts:read16(off) end
		return 0
	end
	return self.io[off + 1] or 0
end

function MemoryBus:writeIO16(off: number, value: number)
	off = bit32.band(off, 0x3FE)
	value = bit32.band(value, 0xFFFF)
	if off <= 0x056 then
		if self.ppu then self.ppu:write16(off, value) end
	elseif off >= 0x060 and off <= 0x0A8 then
		if self.sound then self.sound:write16(off, value) end
	elseif off >= 0x0B0 and off <= 0x0DF then
		if self.dma then self.dma:write16(off, value) end
	elseif off >= 0x100 and off <= 0x10F then
		if self.timers then self.timers:write16(off, value) end
	elseif off >= 0x130 and off <= 0x132 then
		if self.keypad then self.keypad:write16(off, value) end
	elseif off >= 0x200 and off <= 0x208 then
		if self.interrupts then self.interrupts:write16(off, value) end
	else
		self.io[off + 1] = value
	end
end

return MemoryBus
