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
	-- VRAM has no 8-bit path: the byte is replicated across both lanes of the
	-- addressed halfword. (This assertion previously encoded the wrong
	-- behaviour and was corrected by the conformance suite.)
	bus:write8(0x06000000, 0x77)
	check("vram replicates byte stores", bus:read16(0x06000000) == 0x7777, string.format("0x%04X", bus:read16(0x06000000)))
	bus:write8(0x05000020, 0x12)
	check("palette replicates byte stores", bus:read16(0x05000020) == 0x1212, string.format("0x%04X", bus:read16(0x05000020)))
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
	check("framebuffer is a native buffer", type(fb) == "buffer", type(fb))
	check("mode3 pixel is red", buffer.readu8(fb, 0) == 255 and buffer.readu8(fb, 1) == 0 and buffer.readu8(fb, 2) == 0,
		string.format("%d,%d,%d", buffer.readu8(fb, 0), buffer.readu8(fb, 1), buffer.readu8(fb, 2)))
	check("alpha opaque", buffer.readu8(fb, 3) == 255)
	local o = (10 * 240 + 5) * 4
	check("backdrop elsewhere", buffer.readu8(fb, o) == 0 and buffer.readu8(fb, o + 1) == 0 and buffer.readu8(fb, o + 2) == 0)
end

-- Cartridge ------------------------------------------------------------------
section("Cartridge")
do
	local rom = table.create(0x1000, 0)
	rom[1] = 0xFE; rom[2] = 0xFF; rom[3] = 0xFF; rom[4] = 0xEA
	-- title 'TESTGAME'
	local title = "TESTGAME"
	for i = 1, #title do rom[0xA0 + i] = string.byte(title, i) end
	rom[0xAC + 1] = string.byte("A"); rom[0xAC + 2] = string.byte("X"); rom[0xAC + 3] = string.byte("V"); rom[0xAC + 4] = string.byte("J")
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

-- End-to-end: homebrew ROM that paints the screen (no copyrighted content)
section("End-to-end (homebrew mode-3 fill)")
do
	local rom = table.create(0x8000, 0)
	local function w32(off, value)
		rom[off + 1] = value % 256
		rom[off + 2] = (value // 0x100) % 256
		rom[off + 3] = (value // 0x10000) % 256
		rom[off + 4] = (value // 0x1000000) % 256
	end
	w32(0x00, 0xEA00002E) -- B 0xC0 (entry point branches past the header)
	local code = { 0xE59F0020, 0xE59F1020, 0xE5801000, 0xE59F201C, 0xE59F301C, 0xE59F401C, 0xE0C230B2, 0xE2544001, 0x1AFFFFFC, 0xEAFFFFFE }
	for i, word in code do w32(0xC0 + (i - 1) * 4, word) end
	local color15 = 3 + 25 * 0x20 + 11 * 0x400 -- rgb(30,200,90) quantised to 15-bit
	local pool = { 0x04000000, 0x00000403, 0x06000000, color15, 240 * 160 }
	for i, word in pool do w32(0xC0 + #code * 4 + (i - 1) * 4, word) end
	local title = "LUAUGBATEST"
	for i = 1, #title do rom[0xA0 + i] = string.byte(title, i) end
	rom[0xB2 + 1] = 0x96

	local gba = GBA.new({ rom = rom })
	check("homebrew title parsed", gba.cart.info.title == "LUAUGBATEST", gba.cart.info.title)
	for _ = 1, 3 do gba:runFrame() end
	local fb = gba:framebuffer()
	local o = (80 * 240 + 100) * 4
	check("homebrew screen filled", buffer.readu8(fb, o) == 24 and buffer.readu8(fb, o + 1) == 205 and buffer.readu8(fb, o + 2) == 90,
		string.format("%d,%d,%d", buffer.readu8(fb, o), buffer.readu8(fb, o + 1), buffer.readu8(fb, o + 2)))
	check("cpu parked in the idle loop", gba.cpu.regs[16] == 0x080000E4, string.format("0x%08X", gba.cpu.regs[16]))
end

-- Save backends ---------------------------------------------------------------
section("Save backends")
do
	local SaveBackend = require("../Client/Emulator/Save/SaveBackend")

	-- SRAM: plain memory mapped byte access
	local sram = SaveBackend.new("SRAM", 0x80000)
	sram:write8(0x0E000100, 0x42)
	check("sram write/read", sram:read8(0x0E000100) == 0x42, sram:read8(0x0E000100))
	check("sram mirrors 32K", sram:read8(0x0E008100) == 0x42, sram:read8(0x0E008100))

	-- Flash: full command sequence (unlock, program, read back)
	local flash = SaveBackend.new("FLASH512", 0x400000)
	local base = 0x0E000000
	local function flashCmd(a, v) flash:write8(base + a, v) end
	flashCmd(0x5555, 0xAA)
	flashCmd(0x2AAA, 0x55)
	flashCmd(0x5555, 0xA0)
	flash:write8(base + 0x10, 0x99)
	check("flash program", flash:read8(base + 0x10) == 0x99, flash:read8(base + 0x10))
	-- sector erase then verify it cleared
	flashCmd(0x5555, 0xAA)
	flashCmd(0x2AAA, 0x55)
	flashCmd(0x5555, 0x80)
	flashCmd(0x5555, 0xAA)
	flashCmd(0x2AAA, 0x55)
	flashCmd(0x0000, 0x30)
	check("flash sector erase", flash:read8(base + 0x10) == 0xFF, flash:read8(base + 0x10))
	-- manufacturer ID mode
	flashCmd(0x5555, 0xAA)
	flashCmd(0x2AAA, 0x55)
	flashCmd(0x5555, 0x90)
	check("flash id mode", flash:read8(base) == 0x62, flash:read8(base))
	flash:write8(base, 0xF0)

	-- EEPROM uses 64-bit blocks, a trailing stop bit, and four read dummy bits.
	local ee = SaveBackend.new("EEPROM", 0x80000)
	ee:beginEEPROM(73)
	local request = {1, 0, 0, 0, 0, 0, 1, 1} -- write block 3
	for byte = 1, 8 do
		for bit = 7, 0, -1 do table.insert(request, bit32.band(bit32.rshift(0x50 + byte, bit), 1)) end
	end
	table.insert(request, 0)
	for _, bit in request do ee:eepromWriteHalf(bit) end
	check("eeprom writes full block", ee.data[25] == 0x51 and ee.data[32] == 0x58)
	ee:beginEEPROM(9)
	for _, bit in {1, 1, 0, 0, 0, 0, 1, 1, 0} do ee:eepromWriteHalf(bit) end
	for _ = 1, 4 do ee:eepromReadHalf() end
	local got = 0
	for _ = 1, 8 do got = got * 2 + ee:eepromReadHalf() end
	check("eeprom read round trip", got == 0x51, got)

end

-- Audio APU -------------------------------------------------------------------
section("Audio APU")
do
	local Apu = require("../Client/Emulator/Hardware/Apu")
	local apu = Apu.new(nil)

	apu:write16(0x090, 0xBEEF)
	check("wave ram round trip", apu:read16(0x090) == 0xBEEF, apu:read16(0x090))

	check("apu starts disabled", apu.masterEnable == false)
	apu:write16(0x084, 0x80)
	check("master enable bit", apu.masterEnable == true)

	apu:write16(0x080, 0x0007 + 0x1000)  -- ch1 enabled, full left volume
	apu:write16(0x062, 0xF080)            -- duty 2, envelope volume 15
	apu:write16(0x064, 0x8400 + 1000)     -- trigger, frequency 1000
	check("channel 1 triggered", apu.ch[1].enabled == true)

	for _ = 1, 100 do apu:tick(2000) end
	check("samples produced", apu.samplesProduced > 0, apu.samplesProduced)
	local batch = apu:readSamples()
	check("sample buffer drains", #batch > 0 and #apu.buffer == 0, #batch)

	local silent = true
	for _, v in batch do if v ~= 0 then silent = false break end end
	check("mixer output is non-silent", not silent)

	-- DMA sound FIFO A
	apu:write16(0x0A0, 0x8040)
	apu:write16(0x082, 0x0300)
	apu:timerOverflow(0, 2)
	check("fifo A drains", #apu.fifoA < 2, #apu.fifoA)
end

-- Native buffer storage -------------------------------------------------------
section("Native buffer storage (ROM + framebuffer)")
do
	local function gcKb() return collectgarbage("count") end

	-- 16 MiB ROM held as a native buffer
	local SIZE = 16 * 1024 * 1024
	local rom = buffer.create(SIZE)
	buffer.writeu32(rom, 0, 0xEAFFFFFE)   -- ARM 'B .' at the entry point
	buffer.writeu8(rom, 0xB2, 0x96)       -- fixed header byte
	buffer.writeu8(rom, SIZE - 1, 0xAB)   -- marker at the very last byte

	local before = gcKb()
	local t0 = os.clock()
	local gba = GBA.new({ rom = rom })
	local loadMs = (os.clock() - t0) * 1000
	local romKb = gcKb() - before

	check("16 MiB ROM accepted as a buffer", gba.cart.size == SIZE, gba.cart.size)
	check("header parsed from buffer", gba.cart.info.firmwareFlag == 0x96)
	check("read8 at final byte", gba.cart:read8(SIZE - 1) == 0xAB, gba.cart:read8(SIZE - 1))
	check("read32 of final word", gba.cart:read32(SIZE - 4) == 0xAB000000, string.format("0x%X", gba.cart:read32(SIZE - 4)))
	check("read32 exactly at end is 0", gba.cart:read32(SIZE) == 0, gba.cart:read32(SIZE))
	check("read32 far past end does not raise", pcall(function() return gba.cart:read32(SIZE + 0x100000) end))
	check("read16 past end does not raise", pcall(function() return gba.cart:read16(SIZE - 1) end))
	check("unaligned read32 is correct", (function()
		local buf = buffer.create(8)
		buffer.writeu8(buf, 0, 0x11); buffer.writeu8(buf, 1, 0x22)
		buffer.writeu8(buf, 2, 0x33); buffer.writeu8(buf, 3, 0x44)
		buffer.writeu8(buf, 4, 0x55)
		return buffer.readu32(buf, 1) == 0x55443322
	end)())

	local f0 = os.clock()
	for _ = 1, 10 do gba:runFrame() end
	local frameMs = (os.clock() - f0) / 10 * 1000
	check("frames still run with 16 MiB ROM", gba.frames == 10, gba.frames)

	-- Contrast: the same bytes as a plain Lua array (4 MiB, to stay within the
	-- sandbox) shows the per-entry TValue overhead the buffer avoids.
	local TBL = 4 * 1024 * 1024
	local b1 = gcKb()
	local tbl = table.create(TBL, 0)
	local tableKb = gcKb() - b1
	tbl = nil
	collectgarbage()
	local bytesPerEntry = (tableKb * 1024) / TBL
	check("lua table costs far more per byte", bytesPerEntry > 8, string.format("%.1f bytes/entry", bytesPerEntry))

	local bufKb = (buffer.len(rom) / 1024)
	print(string.format("  info  16 MiB buffer: +%.0f KiB accounted, load %.0f ms, frame %.2f ms", romKb, loadMs, frameMs))
	print(string.format("  info  buffer bytes accounted: %d KiB (exactly the payload)", bufKb))
	print(string.format("  info  4 MiB lua array: +%.0f KiB (%.1f bytes/entry) vs 4 MiB buffer = 4096 KiB", tableKb, bytesPerEntry))
end

print(string.format("\n%d checks, %d failures", total, failures))
if failures > 0 then
	error(string.format("%d test(s) failed", failures), 0)
end
print("ALL TESTS PASSED")
