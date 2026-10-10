--!nocheck
-- Synthetic workloads only: no commercial ROM required. Timing is reported,
-- never used as a flaky CI gate. Correctness is compared to normal execution.
local GBA = require("../Client/Emulator/GBA")
local Demo = require("../Client/Emulator/DemoROM")
local IdleLoop = require("../Client/Emulator/CPU/IdleLoop")
local Config = require("../Shared/Config")
local Snapshot = require("../Client/Emulator/Save/SaveState")
local total = 0
local function check(name, condition)
	assert(condition, name); total += 1; print("PASS " .. name)
end
local function equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "buffer" then return buffer.tostring(a) == buffer.tostring(b) end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not equal(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
local function code(gba, ops)
	for i, op in ops do gba.bus:write16(0x03001000 + (i - 1) * 2, op) end
	local cpu = gba.cpu
	cpu.thumb = true; cpu.regs[16] = 0x03001000
	cpu.regs[2], cpu.regs[3] = 0x02001000, 1
	return cpu
end
local function waitMachine(rom)
	local gba = GBA.new({rom = rom})
	code(gba, {0x8808, 0x4010, 0x2800, 0xD0FB, 0x2000, 0x8008, 0xE7F8})
	local bus = gba.bus
	bus:write16(0x02001002, 1)
	bus:write32(0x040000B0, 0x02001002)
	bus:write32(0x040000B4, 0x02001000)
	bus:write32(0x040000B8, 0x93400001) -- repeated VBlank DMA sets the polled flag
	return gba
end
local rom = Demo.create()
local gba = waitMachine(rom)
for _ = 1, 4 do gba:stepInstruction() end
local before = Snapshot.save(gba)
local loop = IdleLoop.probe(gba.cpu)
check("unchanged RAM poll qualifies", loop and loop.cycles == 8 and loop.instructions == 4)
check("probe leaves the entire machine unchanged", equal(before, Snapshot.save(gba)))
check("wait skip advances cycles and records saved work", gba:skipIdle(loop) and gba.cpu.idleCycles > 0)
check("wait skip stops before PPU boundary", gba.ppu.dot < 1006)
gba.interrupts.ie, gba.interrupts.ime, gba.interrupts.if_ = 1, 1, 1
gba.cpu.irqDisable = false
check("pending interrupt prevents a skip", not gba:skipIdle(loop))
gba.interrupts:reset()
gba.cpu.irqDisable = true
gba.bus:write16(0x02001000, 1)
check("changed polled memory resumes ordinary execution", IdleLoop.probe(gba.cpu) == nil)
gba:reset()
code(gba, {0x3801, 0xD1FD}); gba.cpu.regs[1] = 100
check("countdown loops cannot be skipped", IdleLoop.probe(gba.cpu) == nil)
code(gba, {0x8008, 0xE7FD})
check("loops with stores cannot be skipped", IdleLoop.probe(gba.cpu) == nil)
code(gba, {0x8808, 0x4010, 0x2800, 0xD0FB}); gba.cpu.regs[2] = 0x04000006
check("volatile LCD reads cannot be skipped", IdleLoop.probe(gba.cpu) == nil)
code(gba, {0xBE00, 0xE7FD})
check("unknown or exception opcodes cannot be skipped", IdleLoop.probe(gba.cpu) == nil)
code(gba, {0x8808, 0x4010, 0x2800, 0xD0FB})
for _ = 1, 4 do gba:stepInstruction() end
gba.bus:write16(0x03001000, 0x8008)
check("self-modified loop is rechecked", IdleLoop.probe(gba.cpu) == nil)
gba:reset()
gba.bus:write32(0x03001000, 0xEAFFFFFE)
gba.cpu.regs[16] = 0x03001000
check("ARM branch-to-self qualifies", IdleLoop.probe(gba.cpu).cycles == 3)
gba.bus:write32(0x03001000, 0xEBFFFFFE)
check("branch with link cannot be skipped", IdleLoop.probe(gba.cpu) == nil)

-- Real IRQ dispatch must still execute the handler, acknowledge IF, and wake
-- the waiting software. The flag write is done by the emulated CPU itself.
local function irqMachine()
	local machine = waitMachine(rom)
	machine.dma:reset()
	local handler = {0xE59F0014, 0xE3A01001, 0xE1C010B0, 0xE59F000C,
		0xE1C010B0, 0xE12FFF1E, 0xE1A00000, 0x02001000, 0x04000202}
	for i, word in handler do machine.bus:write32(0x03000200 + (i - 1) * 4, word) end
	machine.bus:write32(0x03007FFC, 0x03000200)
	machine.ppu.dispstat = 8
	machine.interrupts.ie, machine.interrupts.ime = 1, 1
	machine.cpu.irqDisable = false
	return machine
end
for _, spec in {{"DMA", waitMachine}, {"IRQ", irqMachine}} do
	local reference, fast = spec[2](rom), spec[2](rom)
	for frame = 1, 4 do
		Config.CORE.idleLoopSkip = false; reference:runFrame()
		Config.CORE.idleLoopSkip = true; fast:runFrame()
		local a, b = Snapshot.save(reference), Snapshot.save(fast)
		a.cpu.idleCycles, b.cpu.idleCycles = nil, nil
		check(spec[1] .. " normal and fast state agree after frame " .. frame, equal(a, b))
	end
	check(spec[1] .. " workload actually skipped wait iterations", fast.cpu.idleCycles > 100000)
end
-- Boundaries for timer IRQs, audio clocks and HALT progress.
local reference, fast = waitMachine(rom), waitMachine(rom)
for _, machine in {reference, fast} do
	machine.bus:write16(0x04000100, 0xFF00); machine.bus:write16(0x04000102, 0xC0)
	machine.apu:write16(0x084, 0x80); machine.apu:write16(0x080, 0x1177)
	machine.apu:write16(0x062, 0xF040); machine.apu:write16(0x064, 0x87E1)
end
for frame = 1, 2 do
	Config.CORE.idleLoopSkip = false; reference:runFrame()
	Config.CORE.idleLoopSkip = true; fast:runFrame()
	local a, b = Snapshot.save(reference), Snapshot.save(fast)
	a.cpu.idleCycles, b.cpu.idleCycles = nil, nil
	check("timer/audio state matches normal execution " .. frame, equal(a, b))
end
check("audio still produces samples with fast waits", fast.apu.samplesProduced > 0)
reference, fast = waitMachine(rom), waitMachine(rom)
fast.ppu.renderEvery = 3
for frame = 1, 4 do
	for _, machine in {reference, fast} do machine.bus:write16(0x05000000, frame) end
	reference:runFrame(); fast:runFrame()
	local a, b = Snapshot.save(reference), Snapshot.save(fast)
	for _, name in {"cpu", "bus", "timers", "dma", "interrupts", "keypad", "apu"} do
		check("raster skipping preserves " .. name .. " frame " .. frame, equal(a[name], b[name]))
	end
	check("raster decision latched for whole frame " .. frame, fast.ppu.frameRendered == (frame == 1 or frame == 4))
	if frame == 2 or frame == 3 then
		check("skipped raster preserves previous display " .. frame, buffer.readu32(fast:framebuffer(), 0) == fast.ppu.RGBA_LUT[2])
	end
end

-- Golden scanline fingerprints from f6fed8d's renderer, covering every text
-- map size, colour depth, flips in patterned map entries, mosaic and scroll.
gba = GBA.new({rom = rom})
for i = 1, #gba.bus.vram do gba.bus.vram[i] = (i * 7 + (i // 64) * 11) % 256 end
for i = 0, 255 do gba.bus:write16(0x05000000 + i * 2, (i * 73) % 32768) end
gba.ppu.dispcnt = 0x100
local expected = {1993092153,2532543040,1905266816,6006586,2632529656,274492724,916972544,3759244532,
	3127462616,2317777208,3636491008,3225355218,2395888640,857603132,2304924416,264201733,
	1183379929,3737700930,295529728,828568490,3930001672,1843962420,2730471936,3755876980,
	3529305727,4044253032,2615741184,1855068114,3327574784,2747903580,1085876992,1285520075}
local case = 0
for size = 0, 3 do for depth = 0, 1 do for mosaic = 0, 1 do for scroll = 0, 1 do
	case += 1
	local ppu = gba.ppu
	ppu.bgcnt[1] = size * 0x4000 + 24 * 0x100 + depth * 0x80 + mosaic * 0x40
	ppu.mosaic, ppu.bghofs[1], ppu.bgvofs[1] = 3, scroll == 0 and 0 or 253, (case * 97) % 512
	ppu:_renderScanline((case * 17) % 160)
	local hash = 0
	for _, pixel in ppu.scanline do hash = (hash * 65599 + pixel) % 4294967296 end
	check("tile renderer golden scanline " .. case, hash == expected[case])
end end end end

gba = waitMachine(rom)
gba.bus:write16(0x04000100, 0xFFF8); gba.bus:write16(0x04000102, 0xC0)
check("next event includes timer overflow", gba:nextEventCycles() == 8)
gba.timers:reset(); gba.apu.masterEnable = true
check("next event includes audio sample clock", gba:nextEventCycles() == 512)
gba.apu.ch[1].enabled = true; gba.apu.ch[1].timer = 7
check("next event includes waveform edge", gba:nextEventCycles() == 7)
gba = irqMachine(); gba.cpu.halted = true
gba:runFrame()
local woke = false
for _ = 1, 100 do
	gba:stepInstruction()
	if not gba.cpu.halted and gba.bus:read16(0x02001000) == 1 and gba.interrupts.if_ == 0 then woke = true; break end
end
check("HALT resumes through real IRQ handler", woke)

-- RAM fast paths must preserve byte-lane/mirror/unaligned behavior.
for _, spec in {{0x02000000, 0x40000}, {0x03000000, 0x8000}} do
	local base, size = spec[1], spec[2]
	for offset = -4, 4 do gba.bus:write8(base + size + offset, (offset + 16) * 7) end
	for offset = size - 3, size + 2 do
		local addr = base + offset
		local v = 0
		for byte = 0, 3 do v += gba.bus:read8(addr + byte) * 256 ^ byte end
		check("RAM word mirror/unaligned " .. addr, gba.bus:read32(addr) == v)
		check("RAM halfword mirror/unaligned " .. addr, gba.bus:read16(addr) == v % 65536)
	end
end
local times = {}
for _, fast in {false, true} do
	Config.CORE.idleLoopSkip = fast
	local machine = waitMachine(rom)
	for _ = 1, 2 do machine:runFrame() end
	local start = os.clock()
	for _ = 1, 12 do machine:runFrame() end
	local ms = (os.clock() - start) * 1000 / 12
	times[fast and 2 or 1] = ms
	print(string.format("Synthetic RAM-poll workload, skip=%s: %.2f ms/frame (%.1f FPS)", tostring(fast), ms, 1000 / ms))
end
Config.CORE.idleLoopSkip = true
print(string.format("Synthetic wait speedup %.2fx; %d performance correctness checks passed", times[1] / times[2], total))

-- Retain the original sliced-demo timing probe, using the balanced budgets.
for _, budget in {8, 12} do
	local machine = GBA.new({rom = Demo.create()})
	local durations = {}
	for _ = 1, 90 do
		local started = os.clock()
		machine:runFrame(budget)
		table.insert(durations, (os.clock() - started) * 1000)
	end
	table.sort(durations)
	local sum = 0
	for _, duration in durations do sum += duration end
	print(string.format("demo budget=%dms mean=%.2fms p95=%.2fms max=%.2fms emulatedFrames=%d slices=%d",
		budget, sum / #durations, durations[math.ceil(#durations * 0.95)], durations[#durations], machine.frames, #durations))
end
