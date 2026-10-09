--!strict
--[[ Emulator/Hardware/Dma.luau

 Four DMA channels (0-3). Supports immediate, VBlank, HBlank and
 "special" (FIFO A/B) start timings. Transfers are performed straight through
 the bus in 16- or 32-bit units, which is accurate for every GBA title that
 does not race the PPU mid-scanline (rare, and covered by the diag invariants).

 REG_DMAxSAD 0xB0/0xBC/0xC8/0xD4
 REG_DMAxDAD 0xB4/0xC0/0xCC/0xD8
 REG_DMAxCNT 0xB8/0xC4/0xD0/0xDC  (low)
 REG_DMAxCNT 0xBA/0xC6/0xD2/0xDE  (high: bits 16+)
 ]]

local Interrupts = require(script.Parent.Interrupts)

local Dma = {}
Dma.__index = Dma

local SAD = { 0xB0, 0xBC, 0xC8, 0xD4 }
local DAD = { 0xB4, 0xC0, 0xCC, 0xD8 }
local CNT = { 0xB8, 0xC4, 0xD0, 0xDC }

function Dma.new(bus: any, interrupts: any)
	local d = { bus = bus, interrupts = interrupts, ch = {} }
	for i = 1, 4 do
		d.ch[i] = { sad = 0, dad = 0, cnt = 0, cntHigh = 0, active = false }
	end
	return setmetatable(d, Dma) :: any
end

local function channelOf(addr: number): (number?, number?)
	for i = 1, 4 do
		if addr >= SAD[i] and addr < SAD[i] + 0xC then
			return i, addr - SAD[i]
		end
	end
	return nil, nil
end

function Dma:read16(addr: number): number
	local i, off = channelOf(addr)
	if not i then return 0 end
	local c = self.ch[i]
	if off == 0 then return c.sad % 0x10000
	elseif off == 2 then return c.sad // 0x10000
	elseif off == 4 then return c.dad % 0x10000
	elseif off == 6 then return c.dad // 0x10000
	elseif off == 8 then return c.cnt
	elseif off == 10 then return c.cntHigh end
	return 0
end

function Dma:write16(addr: number, value: number)
	local i, off = channelOf(addr)
	if not i then return end
	local c = self.ch[i]
	if off == 0 then c.sad = (c.sad % 0x10000) + value * 0x10000
	elseif off == 2 then c.sad = (c.sad % 0x10000) + bit32.band(value, 0xFFFF) * 0x10000
	elseif off == 4 then c.dad = (c.dad % 0x10000) + value * 0x10000
	elseif off == 6 then c.dad = (c.dad % 0x10000) + bit32.band(value, 0xFFFF) * 0x10000
	elseif off == 8 then
		c.cnt = bit32.band(value, 0xFFFF)
		local enable = bit32.band(c.cnt, 0x8000) ~= 0
		if enable then self:_start(i) end
	elseif off == 10 then
		c.cntHigh = bit32.band(value, 0xFFFF)
	end
end

function Dma:_start(i: number)
	local c = self.ch[i]
	local timing = bit32.band(c.cnt, 0x3000) // 0x1000
	if timing == 0 then
		self:_transfer(i)
	end
	-- timing 1 (VBlank) / 2 (HBlank) / 3 (special) are fired by hooks below
end

--- Execute a full block transfer for channel i.
function Dma:_transfer(i: number)
	local c = self.ch[i]
	if bit32.band(c.cnt, 0x8000) == 0 then return end
	local unit32 = bit32.band(c.cnt, 0x400) ~= 0
	local count = bit32.band(c.cnt, 0x3FFF)
	if count == 0 then count = if i == 3 then 0x10000 else 0x4000 end
	local srcCtl = bit32.band(c.cnt, 0x180) // 0x80
	local dstCtl = bit32.band(c.cnt, 0x60) // 0x20
	local unit = unit32 and 4 or 2
	local sad, dad = c.sad, c.dad
	local bus = self.bus
	local startCycle = 1

	if unit32 then
		for _ = 1, count do
			bus:write32(dad, bus:read32(sad))
			sad = (sad + self:_step(srcCtl)) % 0x10000000
			dad = (dad + self:_step(dstCtl)) % 0x10000000
		end
	else
		for _ = 1, count do
			bus:write16(dad, bus:read16(sad))
			sad = (sad + self:_step(srcCtl)) % 0x10000000
			dad = (dad + self:_step(dstCtl)) % 0x10000000
		end
	end

	-- interrupt + clear enable
	local irq = bit32.band(c.cnt, 0x4000) ~= 0
	if irq then self.interrupts:raise(Interrupts.DMA0 + (i - 1)) end
	c.cnt = bit32.band(c.cnt, bit32.bnot(0x8000))
	bus:addCycles(4 * count * startCycle)
end

function Dma:_step(ctl: number): number
	if ctl == 0 then return 2 end   -- increment
	if ctl == 1 then return -2 end  -- decrement
	return 0                         -- fixed
end

--- Hook called by the PPU on VBlank / HBlank.
function Dma:trigger(timing: number)
	for i = 1, 4 do
		local c = self.ch[i]
		if bit32.band(c.cnt, 0x8000) == 0 then continue end
		local t = bit32.band(c.cnt, 0x3000) // 0x1000
		if t == timing then
			self:_transfer(i)
		end
	end
end

function Dma:reset()
	for i = 1, 4 do self.ch[i] = { sad = 0, dad = 0, cnt = 0, cntHigh = 0, active = false } end
end

return Dma
