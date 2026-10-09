--!strict
--[[ Emulator/Cart/HLEBIOS.luau

 High-level emulation of the GBA BIOS SWI interface. This lets commercial ROMs
 boot and run *without* shipping Nintendo's copyrighted 16 KiB BIOS image: each
 SWI is intercepted and reimplemented in Luau.

 If the user supplies a real bios.bin, GBA.luau will not install this module and
 SWIs vector through 0x08 instead (max accuracy).

 Register conventions follow the official BIOS: R0..R3 arguments, results in
 R0/R1, R4-R11/R12 preserved, flags undefined unless stated.
 ]]

local Interrupts = require(script.Parent.Parent.Hardware.Interrupts)

local HLEBIOS = {}
HLEBIOS.__index = HLEBIOS

function HLEBIOS.new(bus: any)
	return setmetatable({ bus = bus, cpu = nil }, HLEBIOS) :: any
end

-- Helpers -------------------------------------------------------------------

local function signed(v: number): number
	v %= 0x100000000
	if v >= 0x80000000 then return v - 0x100000000 end
	return v
end

local function divArm(cpu, arm: boolean)
	local n = cpu.regs[1]
	local d = cpu.regs[2]
	if arm then n, d = d, n end
	if d == 0 then
		cpu.regs[1] = 0
		cpu.regs[2] = 0
		cpu.regs[4] = 0
		return
	end
	local sn, sd = signed(n), signed(d)
	local q = math.floor(math.abs(sn) / math.abs(sd))
	local r = math.abs(sn) % math.abs(sd)
	if (sn < 0) ~= (sd < 0) then q = -q end
	if sn < 0 then r = -r end
	cpu.regs[1] = q % 0x100000000
	cpu.regs[2] = r % 0x100000000
	cpu.regs[4] = math.abs(q) % 0x100000000
end

local function sqrt(cpu)
	local v = cpu.regs[1]
	cpu.regs[1] = math.floor(math.sqrt(v)) % 0x100000000
end

local function arcTan(cpu)
	local v = signed(cpu.regs[1])
	local a = math.atan(v / 65536)
	cpu.regs[1] = math.floor(a / (math.pi / 2) * 16384 + 0.5) % 0x10000
end

local function arcTan2(cpu)
	local x = signed(cpu.regs[1])
	local y = signed(cpu.regs[2])
	local a = math.atan(y, x)
	cpu.regs[1] = math.floor(a / (2 * math.pi) * 65536 + 0.5) % 0x10000
end

local function cpuSet(cpu, fast: boolean)
	local src = cpu.regs[1]
	local dst = cpu.regs[2]
	local ctrl = cpu.regs[3]
	local count = bit32.band(ctrl, 0x1FFFFF)
	local word = bit32.band(ctrl, 0x4000000) ~= 0
	local fill = bit32.band(ctrl, 0x1000000) ~= 0
	local bus = cpu.bus
	if word then
		local value = bus:read32(src)
		for i = 1, count do
			bus:write32(dst + (i - 1) * 4, value)
			if not fill then value = bus:read32(src + i * 4) end
		end
	else
		local value = bus:read16(src)
		for i = 1, count do
			bus:write16(dst + (i - 1) * 2, value)
			if not fill then value = bus:read16(src + i * 2) end
		end
	end
end

local function lz77(cpu, vram: boolean)
	local src = cpu.regs[1]
	local dst = cpu.regs[2]
	local bus = cpu.bus
	local header = bus:read32(src)
	src += 4
	local size = bit32.band(header, 0xFFFFFF)
	local out = 0
	while out < size do
		local flags = bus:read8(src)
		src += 1
		for bit = 0, 7 do
			if out >= size then break end
			if bit32.band(flags, bit32.lshift(1, bit)) == 0 then
				bus:write8(dst + out, bus:read8(src)); src += 1; out += 1
			else
				local b1 = bus:read8(src)
				local b2 = bus:read8(src + 1)
				src += 2
				local length = (b1 // 16) + 3
				local disp = ((b1 % 16) * 256 + b2) + 1
				for _ = 1, length do
					if out >= size then break end
					bus:write8(dst + out, bus:read8(dst + out - disp))
					out += 1
				end
			end
		end
	end
end

local function rlUncomp(cpu, vram: boolean)
	local src = cpu.regs[1]
	local dst = cpu.regs[2]
	local bus = cpu.bus
	local header = bus:read32(src)
	src += 4
	local size = bit32.band(header, 0xFFFFFF)
	local out = 0
	while out < size do
		local flag = bus:read8(src); src += 1
		if bit32.band(flag, 0x80) ~= 0 then
			local count = (flag % 128) + 3
			local value = bus:read8(src); src += 1
			for _ = 1, count do bus:write8(dst + out, value); out += 1 end
		else
			local count = flag + 1
			for _ = 1, count do bus:write8(dst + out, bus:read8(src)); src += 1; out += 1 end
		end
	end
end

local function halt(cpu)
	cpu.halted = true
end

local function intrWait(cpu, discardOld: boolean)
	local flags = cpu.regs[1]
	if discardOld then
		cpu.bus.interrupts.if_ = 0
	end
	cpu._intrWaitFlags = flags
	cpu.halted = true
end

local function registerRamReset(cpu)
	local flags = cpu.regs[1]
	local bus = cpu.bus
	if bit32.band(flags, 1) ~= 0 then
		for i = 1, 0x8000 do bus.iwram[i] = 0 end
	end
	if bit32.band(flags, 2) ~= 0 then
		for i = 1, 0x40000 do bus.ewram[i] = 0 end
	end
end

-- Dispatch ------------------------------------------------------------------

HLEBIOS.TABLE = {
	[0x00] = function(cpu) cpu.halted = true end,                 -- SoftReset
	[0x01] = registerRamReset,
	[0x02] = halt,
	[0x03] = halt,                                                 -- Stop
	[0x04] = function(cpu) intrWait(cpu, false) end,               -- IntrWait
	[0x05] = function(cpu) intrWait(cpu, true) end,                -- VBlankIntrWait
	[0x06] = function(cpu) divArm(cpu, false) end,
	[0x07] = function(cpu) divArm(cpu, true) end,
	[0x08] = sqrt,
	[0x09] = arcTan,
	[0x0A] = arcTan2,
	[0x0B] = function(cpu) cpuSet(cpu, false) end,
	[0x0C] = function(cpu) cpuSet(cpu, true) end,
	[0x0D] = function(cpu) cpu.regs[1] = 0xBAAE187F end,           -- GetBiosChecksum
	[0x11] = function(cpu) lz77(cpu, false) end,
	[0x12] = function(cpu) lz77(cpu, true) end,
	[0x14] = function(cpu) rlUncomp(cpu, false) end,
	[0x15] = function(cpu) rlUncomp(cpu, true) end,
}

--- Handle a SWI. Returns true when handled in HLE.
function HLEBIOS:call(comment: number, cpu: any): boolean
	local fn = HLEBIOS.TABLE[comment]
	if fn then
		fn(cpu)
		return true
	end
	-- Unknown SWI: nop rather than crash; the diagnostics layer will see the
	-- missing implementation if the game misbehaves.
	return true
end

return HLEBIOS
