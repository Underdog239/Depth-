--!nocheck
local GBA = require("../Client/Emulator/GBA")
local Demo = require("../Client/Emulator/DemoROM")
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
local rom = Demo.create()
local gba = GBA.new({rom = rom})
for i = 0, 31 do gba.bus:write32(0x03001000 + i * 4, 0xE1A00000) end
gba.cpu.regs[16] = 0x03001000
for _ = 1, 10 do gba:stepInstruction() end
check("ordinary instructions accumulate between events", gba.pendingCycles == 10 and gba.bus.cycles == 0)
gba.bus:write16(0x04000100, 0xFFF0)
check("IO write flushes earlier instructions before changing timer", gba.pendingCycles == 0 and gba.bus.cycles == 10)
gba.bus:write16(0x04000102, 0xC0)
for _ = 1, 6 do gba:stepInstruction() end
check("timer read observes pending CPU time", gba.bus:read16(0x04000100) == 0xFFF6 and gba.bus.cycles == 16)
gba.bus:write16(0x04000102, 0)
gba.bus:write16(0x04000100, 0xFFFE)
gba.bus:write16(0x04000102, 0xC0)
gba:stepInstruction()
check("shorter timer deadline invalidates cached batch", gba.bus.tickLimit == 2 and gba.interrupts.if_ == 0)
gba:stepInstruction()
check("timer IRQ dispatches at its event boundary", bit32.band(gba.interrupts.if_, 8) ~= 0)

-- IO reached recursively by sound DMA must not re-dispatch pending cycles.
gba:reset()
gba.apu:write16(0x084, 0x80)
for i = 0, 3 do gba.bus:write32(0x02000100 + i * 4, 0x03020100) end
gba.bus:write32(0x040000BC, 0x02000100)
gba.bus:write32(0x040000C0, 0x040000A0)
gba.bus:write32(0x040000C4, 0xB6400000)
gba.bus:write16(0x04000100, 0xFFFE)
gba.bus:write16(0x04000102, 0x80)
gba.pendingCycles = 2
gba:flushCycles()
check("timer-triggered FIFO IO does not recursively tick", gba.bus.cycles == 2 and gba.pendingCycles == 0 and #gba.apu.fifoA == 16)

-- Check register, memory, timer, waveform and rendered-pixel state against
-- dispatch after every instruction. Both machines execute the same CPU code.
local reference, batched = GBA.new({rom = rom}), GBA.new({rom = rom})
for _, machine in {reference, batched} do
	machine.bus:write16(0x04000100, 0xFF01)
	machine.bus:write16(0x04000102, 0xC0)
	machine.apu:write16(0x084, 0x80)
	machine.apu:write16(0x080, 0x1177)
	machine.apu:write16(0x062, 0xF040)
	machine.apu:write16(0x064, 0x87E1)
end
for part = 1, 8 do
	Config.CORE.tickBatchCycles = 1; reference:runCycles(30000)
	Config.CORE.tickBatchCycles = 64; batched:runCycles(30000)
	check("batched hardware matches instruction dispatch segment " .. part,
		equal(Snapshot.save(reference), Snapshot.save(batched)))
end
local saved = Snapshot.save(batched)
batched:runCycles(4000)
local result = Snapshot.save(batched)
check("snapshot restores pending hardware scheduling", Snapshot.load(batched, saved))
batched:runCycles(4000)
check("restored batching is deterministic", equal(result, Snapshot.save(batched)))

for _, batch in {4, 64} do
	Config.CORE.tickBatchCycles = batch
	local machine = GBA.new({rom = rom})
	for _ = 1, 2 do machine:runFrame() end
	local start = os.clock()
	for _ = 1, 8 do machine:runFrame() end
	print(string.format("Active demo CPU, hardware batch %d: %.2f ms/frame", batch, (os.clock() - start) * 1000 / 8))
end
Config.CORE.tickBatchCycles = 64
print(string.format("%d hardware batching checks passed", total))
