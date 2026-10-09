--!nocheck
--[[ Tests/run.luau

 Runnable test suite for the pure (Roblox-independent) modules. It is executed
 with the standalone Luau binary after tools/prepare_tests.py rewrites the
 Roblox requires into require-by-string paths:

     python3 tools/prepare_tests.py && luau build/Tests/run.luau

 Everything here must pass before the emulator core is considered healthy.
 ]]

-- Minimal Roblox stubs so modules that touch `game` at load time can be loaded.
game = {
	GetService = function(_self, name)
		return { Shared = {} }
	end,
}

local failures = 0
total = 0
local function check(name, cond, detail)
	total += 1
	if cond then
		print(string.format("  ok   %s", name))
	else
		failures += 1
		print(string.format("  FAIL %s%s", name, detail and ("  -> " .. tostring(detail)) or ""))
	end
end

local function section(name)
	print("\n== " .. name)
end

-- Modules -------------------------------------------------------------------
local Base64 = require("../Shared/Base64")
local Classifier = require("../Client/Diagnostics/Classifier")
local Store = require("../Client/Diagnostics/Store")
local StaticScan = require("../Client/Diagnostics/StaticScan")
local MemoryBus = require("../Client/Emulator/Bus/MemoryBus")
local Arm7tdmi = require("../Client/Emulator/CPU/Arm7tdmi")
local Interrupts = require("../Client/Emulator/Hardware/Interrupts")
local Ppu = require("../Client/Emulator/Hardware/Ppu")
local Cartridge = require("../Client/Emulator/Cart/Cartridge")
local GBA = require("../Client/Emulator/GBA")

-- Base64 --------------------------------------------------------------------
section("Base64")
do
	local bytes = {}
	for i = 0, 255 do bytes[i + 1] = i end
	local encoded = Base64.encode(bytes)
	local decoded = Base64.decode(encoded)
	check("round-trip length", #decoded == #bytes, #decoded)
	local same = true
	for i = 1, #bytes do
		if bytes[i] ~= decoded[i] then same = false break end
	end
	check("round-trip content", same)
	check("known vector", Base64.encode({ 77, 97, 110 }) == "TWFu", Base64.encode({ 77, 97, 110 }))
end

-- Classifier -----------------------------------------------------------------
section("Classifier")
do
	check("unfinished: TODO", Classifier.classify("-- TODO: wire this up", "src", nil) == "unfinished")
	check("vulnerability: loadstring", Classifier.classify("loadstring(payload)", "src", nil) == "vulnerability")
	check("bug: divide by zero", Classifier.classify("division by zero in cpu", "src", nil) == "bug")
	check("error: explicit runtime kind", Classifier.classify("something exploded", "src", "runtime-error") == "error")
	local f = Classifier.makeFinding({ message = "-- FIXME", source = "StaticScan:x" })
	check("finding has category", f.category == "unfinished", f.category)
	check("dedup symbol stable", Classifier.symbolFor("bug", "read8(0x1FF)", "bus") == Classifier.symbolFor("bug", "read8(0x200)", "bus"))
end

-- Store ----------------------------------------------------------------------
section("Store")
do
	local store = Store.new(10)
	local a = Classifier.makeFinding({ message = "boom", source = "s", kind = "runtime-error" })
	store:add(a)
	store:add(a)
	check("dedup increments count", store:count() == 1 and store:all()[1].count == 2)
	local b = Classifier.makeFinding({ message = "-- TODO", source = "s" })
	store:add(b)
	check("two distinct findings", store:count() == 2)
	local counts = store:countByCategory()
	check("category counts", counts.error == 1 and counts.unfinished == 1, counts.error)
end

-- StaticScan -----------------------------------------------------------------
section("StaticScan")
do
	local hits = StaticScan.scanSource("-- TODO finish\nlocal f = loadstring('x')\n-- FIXME later\n", "unit.luau")
	local hasTodo, hasLoadstring = false, false
	for _, h in hits do
		if h.category == "unfinished" then hasTodo = true end
		if h.category == "vulnerability" then hasLoadstring = true end
	end
	check("detects TODO/FIXME", hasTodo)
	check("detects loadstring", hasLoadstring)
end

-- Memory bus -----------------------------------------------------------------
section("MemoryBus")
do
	local bus = MemoryBus.new()
	bus:write32(0x02000000, 0xDEADBEEF)
	check("ewram 32-bit round trip", bus:read32(0x02000000) == 0xDEADBEEF, bus:read32(0x02000000))
	bus:write16(0x03000000, 0x1234)
	check("iwram 16-bit round trip", bus:read16(0x03000000) == 0x1234)
	bus:write16(0x06000000, 0x00FF)
	bus:write8(0x06000000, 0x77) -- must be ignored on VRAM
	check("vram ignores 8-bit writes", bus:read16(0x06000000) == 0x00FF, bus:read16(0x06000000))
end

-- CPU: ARM -------------------------------------------------------------------
section("CPU ARM")
do
	local bus = MemoryBus.new()
	local cpu = Arm7tdmi.new(bus)
	cpu:reset(0x08000000)
	cpu:executeARM(0xE3A00005) -- MOV r0, #5
	check("MOV r0,#5", cpu.regs[1] == 5, cpu.regs[1])
	cpu:executeARM(0xE2800003) -- ADD r0, r0, #3
	check("ADD r0,r0,#3", cpu.regs[1] == 8, cpu.regs[1])
	cpu:executeARM(0xE2401001) -- SUB r1, r0, #1
	check("SUB r1,r0,#1", cpu.regs[2] == 7, cpu.regs[2])
	cpu:executeARM(0xE3110008) -- TST r1, #8 (7 AND 8 == 0)
	check("TST sets Z on zero result", cpu.z == true)
end

-- CPU: THUMB -----------------------------------------------------------------
section("CPU THUMB")
do
	local bus = MemoryBus.new()
	local cpu = Arm7tdmi.new(bus)
	cpu:reset(0x08000000)
	cpu.thumb = true
	cpu:executeTHUMB(0x2005) -- MOVS r0, #5
	check("MOVS r0,#5", cpu.regs[1] == 5, cpu.regs[1])
	cpu:executeTHUMB(0x3003) -- ADDS r0, #3
	check("ADDS r0,#3", cpu.regs[1] == 8, cpu.regs[1])
	cpu:executeTHUMB(0x3801) -- SUBS r0, #1
	check("SUBS r0,#1", cpu.regs[1] == 7, cpu.regs[1])
	cpu:executeTHUMB(0x0041) -- LSL r1, r0, #1
	check("LSL r1,r0,#1", cpu.regs[2] == 14, cpu.regs[2])
end

-- PPU ------------------------------------------------------------------------
section("PPU")
do
	local bus = MemoryBus.new()
	local irq = Interrupts.new()
	local ppu = Ppu.new(bus, irq)
	bus.ppu = ppu
	bus:write16(0x04000000, 0x0403) -- mode 3 + BG2 enable
	bus:write16(0x06000000, 0x001F) -- red pixel at (0,0)
	ppu:_renderScanline(0)
	ppu:_blitLine(0)
	local fb = ppu.framebuffer
	check("mode3 pixel is red", fb[1] == 255 and fb[2] == 0 and fb[3] == 0, string.format("%d,%d,%d", fb[1], fb[2], fb[3]))
	check("alpha opaque", fb[4] == 255)
	local fb2 = ppu.framebuffer
	local o = (10 * 240 + 5) * 4
	check("backdrop elsewhere", fb2[o + 1] == 0 and fb2[o + 2] == 0 and fb2[o + 3] == 0)
end

-- Cartridge ------------------------------------------------------------------
section("Cartridge")
do
	local rom = table.create(0x1000, 0)
	rom[1] = 0xFE; rom[2] = 0xFF; rom[3] = 0xFF; rom[4] = 0xEA
	-- title 'TESTGAME'
	local title = "TESTGAME"
	for i = 1, #title do rom[0x00 + i] = string.byte(title, i) end
	rom[0x0C + 1] = string.byte("A"); rom[0x0C + 2] = string.byte("X"); rom[0x0C + 3] = string.byte("V"); rom[0x0C + 4] = string.byte("J")
	rom[0xBE + 1] = 0 -- 32 KiB size index
	local cart = Cartridge.new(rom)
	check("title parsed", cart.info.title == "TESTGAME", cart.info.title)
	check("game code parsed", cart.info.gameCode == "AXVJ", cart.info.gameCode)
	check("save type detected", cart.info.saveType == "EEPROM", cart.info.saveType)
end

-- End-to-end -----------------------------------------------------------------
section("End-to-end (ROM boot + one frame)")
do
	local rom = table.create(0x8000, 0)
	-- ARM 'B .' branch-to-self at the ROM entry point
	rom[1] = 0xFE; rom[2] = 0xFF; rom[3] = 0xFF; rom[4] = 0xEA
	rom[0xB2 + 1] = 0x96
	local gba = GBA.new({ rom = rom })
	check("cpu starts at ROM base", gba.cpu.regs[16] == 0x08000000, string.format("0x%08X", gba.cpu.regs[16]))
	local ok, err = pcall(function() gba:runFrame() end)
	check("runFrame completes", ok, err)
	check("frame counter advanced", gba.frames == 1, gba.frames)
	check("ppu produced a frame", gba.ppu.frame >= 1, gba.ppu.frame)
	check("pc still inside ROM", gba.cpu.regs[16] == 0x08000000, string.format("0x%08X", gba.cpu.regs[16]))
end

print(string.format("\n%d checks, %d failures", total, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
print("ALL TESTS PASSED")
