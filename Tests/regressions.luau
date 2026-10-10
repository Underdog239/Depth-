--!nocheck
local GBA = require("../Client/Emulator/GBA")
local Demo = require("../Client/Emulator/DemoROM")
local Snapshot = require("../Client/Emulator/Save/SaveState")
local Base64 = require("../Shared/Base64")
local Payload = require("../Shared/DiagPayload")
local StaticScan = require("../Client/Diagnostics/StaticScan")
local failures, total = 0, 0
local function check(name, condition)
 total += 1
 print((condition and "PASS " or "FAIL ") .. name)
 if not condition then failures += 1 end
end
local function equal(a, b)
 if type(a) ~= type(b) then return false end
 if type(a) == "buffer" then return buffer.tostring(a) == buffer.tostring(b) end
 if type(a) ~= "table" then return a == b end
 for k, v in a do if not equal(v, b[k]) then return false end end
 for k in b do if a[k] == nil then return false end end
 return true
end
local gba = GBA.new({rom = Demo.create()})
local bus = gba.bus
check("original demo header complement", gba.cart.info.headerChecksumOk)
for _ = 1, 3 do gba:runFrame() end
check("demo paints first and last pixels", bus:read16(0x06000000) == 0x2F23 and bus:read16(0x06012BFE) == 0x2F23)
gba:setKeys(1)
for _ = 1, 3 do gba:runFrame() end
check("demo responds to input", bus:read16(0x06000000) == 1 and bus:read16(0x06012BFE) == 1)

-- DMA through real bus IO, covering both widths, address steps and repeats.
gba:reset()
for i = 0, 3 do bus:write32(0x02000100 + i * 4, 0x11223344 + i) end
bus:write32(0x040000B0, 0x02000100)
bus:write32(0x040000B4, 0x03000200)
bus:write32(0x040000B8, 0x84000004)
check("DMA word addresses and width", bus:read32(0x03000200) == 0x11223344 and bus:read32(0x0300020C) == 0x11223347)
check("DMA immediate clears enable", bit32.band(bus:read16(0x040000BA), 0x8000) == 0)
bus:write32(0x040000B0, 0x02000100)
bus:write32(0x040000B4, 0x03000300)
bus:write32(0x040000B8, 0xA2600002) -- HBlank/repeat/destination reload
check("DMA waits for trigger", bus:read32(0x03000300) == 0)
gba.dma:trigger(2)
check("DMA halfword transfer", bus:read32(0x03000300) == 0x11223344)
gba.dma:trigger(2)
check("DMA repeat advances source and reloads dest", bus:read32(0x03000300) == 0x11223345)
check("DMA repeat stays enabled", bit32.band(bus:read16(0x040000BA), 0x8000) ~= 0)
gba.dma:reset()

-- Short timer periods must count every overflow even when cycles are batched.
bus:write16(0x04000100, 0xFFFE)
bus:write16(0x04000104, 0)
bus:write16(0x04000106, 0x84)
bus:write16(0x04000102, 0x80)
gba.timers:tick(7)
check("timer repeated reload", bus:read16(0x04000100) == 0xFFFF)
check("timer cascades each overflow", bus:read16(0x04000104) == 3)
bus:write16(0x04000100, 0x1234)
check("running timer reload write preserves counter", bus:read16(0x04000100) == 0xFFFF)

bus:write16(0x04000030, 0xFE00)
bus:write16(0x04000040, 0x1122)
bus:write16(0x04000042, 0x3344)
bus:write16(0x04000044, 0x5566)
bus:write16(0x04000048, 0x3F3F)
check("PPU BG3 affine register", gba.ppu.bgpa[2] == -512)
check("PPU window register routing", gba.ppu.winh[2] == 0x3344 and gba.ppu.winv[1] == 0x5566 and gba.ppu.winin == 0x3F3F)
bus:write16(0x05000001, 0x1234)
check("palette halfword preserves lanes", bus:read16(0x05000000) == 0x1234)
bus:write8(0x05000001, 0x56)
check("palette odd byte replicates both lanes", bus:read16(0x05000000) == 0x5656)
bus:write16(0x04000200, 0x1234)
check("IO byte high lane", bus:read8(0x04000201) == 0x12)

-- Snapshot replay exercises all mutable hardware, pending cycles and buffers.
gba:reset()
gba:runCycles(999)
bus:write16(0x04000100, 0xFFFC)
bus:write16(0x04000102, 0x80)
bus:write16(0x04000020, 0x123)
gba.cpu:_setMode(0x11)
gba.cpu.regs[9] = 0xDEADBEEF
gba.apu:write16(0x084, 0x80)
gba.apu:write16(0x0A4, 0x7F80)
local saved = Snapshot.save(gba)
gba:runCycles(2000)
local expected = Snapshot.save(gba)
check("snapshot accepts same cartridge", Snapshot.load(gba, saved))
gba:runCycles(2000)
check("snapshot deterministic replay across hardware", equal(expected, Snapshot.save(gba)))
check("snapshot can be loaded repeatedly", Snapshot.load(gba, saved) and Snapshot.load(gba, saved))
check("snapshot rejects another cartridge", not Snapshot.load(GBA.new({rom = Demo.create()}), saved))
bus:write8(0x0E000000, 0x42)
gba:reset()
check("reset clears RAM and hardware", bus:read32(0x02000100) == 0 and gba.ppu.bgpa[1] == 256 and gba.cpu.sharedLow[1] == 0 and bus.cycles == 0)
check("reset preserves battery save", bus:read8(0x0E000000) == 0x42)

-- BIOS decompression: MSB-first flags, 24-bit size and halfword VRAM stores.
local compressed = {0x10, 6, 0, 0, 0x10, 65, 66, 67, 0, 2}
for i, byte in compressed do bus:write8(0x02000000 + i - 1, byte) end
gba.cpu.regs[1], gba.cpu.regs[2] = 0x02000000, 0x06000000
gba.cpu:swi(0x12)
check("LZ77 VRAM literal/backreference", bus:read32(0x06000000) == 0x41434241 and bus:read16(0x06000004) == 0x4342)
local rle = {0x30, 5, 0, 0, 0x82, 0x77}
for i, byte in rle do bus:write8(0x02000000 + i - 1, byte) end
gba.cpu.regs[1], gba.cpu.regs[2] = 0x02000000, 0x02000100
gba.cpu:swi(0x14)
check("RLE declared output size", bus:read32(0x02000100) == 0x77777777 and bus:read8(0x02000104) == 0x77 and bus:read8(0x02000105) == 0)
for i = 0, 7 do bus:write32(0x02000200 + i * 4, i + 1) end
gba.cpu.regs[1], gba.cpu.regs[2], gba.cpu.regs[3] = 0x02000200, 0x02000300, 8
gba.cpu:swi(0x0C)
check("CpuFastSet always copies words", bus:read32(0x0200031C) == 8)
check("unsupported BIOS call reports failure", not pcall(function() gba.cpu:swi(0xFF) end))

-- IRQ trampoline executes an ordinary game's IWRAM handler and returns.
gba:reset()
local handler = {0xE59F0008, 0xE3A01001, 0xE1C010B0, 0xE12FFF1E, 0x04000202}
for i, word in handler do bus:write32(0x03000100 + (i - 1) * 4, word) end
bus:write32(0x03007FFC, 0x03000100)
gba.interrupts.ie, gba.interrupts.ime = 1, 1
gba.interrupts:raise(0)
gba:runCycles(100)
check("HLE IRQ calls handler and acknowledges", gba.interrupts.if_ == 0)
check("HLE IRQ restores mode and returns to ROM", gba.cpu.mode == 0x1F and gba.cpu.regs[16] >= 0x08000000)

-- Client slices must yield without inventing a completed emulated frame.
local sliced = GBA.new({rom = Demo.create()})
sliced:runFrame(0)
check("client slice yields before full frame", not sliced.ppu.frameComplete and sliced.frames == 0 and sliced.cpu.instructions <= 256)
for _ = 1, 2000 do
 sliced:runFrame(0)
 if sliced.ppu.frameComplete then break end
end
check("client slices eventually complete a frame", sliced.ppu.frameComplete and sliced.frames == 1)

-- EEPROM DMA must advance the source/destination for every serial bit.
local SaveBackend = require("../Client/Emulator/Save/SaveBackend")
gba:reset()
gba.cart.backend = SaveBackend.new("EEPROM", 0x80000)
local request = {1, 0, 0, 0, 0, 0, 0, 1}
for byte = 1, 8 do
 for bit = 7, 0, -1 do table.insert(request, bit32.band(bit32.rshift(byte, bit), 1)) end
end
table.insert(request, 0)
for i, bit in request do bus:write16(0x02000000 + (i - 1) * 2, bit) end
bus:write32(0x040000D4, 0x02000000)
bus:write32(0x040000D8, 0x0D000000)
bus:write32(0x040000DC, 0x80400049) -- DMA3, fixed destination, 73 halfwords
check("DMA EEPROM writes eight-byte block", gba.cart.backend.data[9] == 1 and gba.cart.backend.data[16] == 8)
request = {1, 1, 0, 0, 0, 0, 0, 1, 0}
for i, bit in request do bus:write16(0x02000000 + (i - 1) * 2, bit) end
bus:write32(0x040000D4, 0x02000000)
bus:write32(0x040000DC, 0x80400009)
bus:write32(0x040000D4, 0x0D000000)
bus:write32(0x040000D8, 0x03000200)
bus:write32(0x040000DC, 0x81000044) -- fixed source, 68 halfwords
local serial = 0
for i = 4, 11 do serial = serial * 2 + bus:read16(0x03000200 + i * 2) end
check("DMA EEPROM read advances destination", serial == 1)

-- Timer FIFO selection and sound DMA refill are independent of the sample mixer.
gba:reset()
gba.apu:write16(0x084, 0x80)
gba.apu:write16(0x082, 0x4000) -- FIFO B uses timer 1
bus:write32(0x040000A0, 0x03020100)
bus:write32(0x040000A4, 0x07060504)
gba.apu:timerOverflow(0, 1)
check("sound FIFO A/B register routing", #gba.apu.fifoA == 3 and #gba.apu.fifoB == 4 and gba.apu.fifoB[1] == 4)
gba.apu:timerOverflow(1, 1)
check("sound FIFO B selected timer", #gba.apu.fifoB == 3 and gba.apu.fifoSampleB == 4)
for i = 0, 3 do bus:write32(0x02000100 + i * 4, 0x03020100) end
bus:write32(0x040000BC, 0x02000100)
bus:write32(0x040000C0, 0x040000A0)
bus:write32(0x040000C4, 0xB6400000)
gba.apu:timerOverflow(0, 1)
check("sound DMA refills four words", #gba.apu.fifoA == 18 and gba.dma.ch[2].src == 0x02000110)

for _, invalid in {"A", "!!!!", "AA=A", "=AAA", "AAA=AAAA"} do
 check("base64 rejects " .. invalid, not pcall(Base64.decodeToBuffer, invalid))
end
check("base64 accepts whitespace", Base64.decode(" T W F u \n")[3] == 110)
check("empty/short ROM rejected", not pcall(GBA.new, {rom = buffer.create(4)}))
local clean = Payload.sanitize({category="bug",message="m",symbol="s",severity={},count=0/0,source={},meta={unbounded={}}})
check("remote diagnostics sanitize fields", clean and clean.severity == "info" and clean.count == 1 and clean.source == "" and clean.meta == nil)
check("remote diagnostics reject invalid category", Payload.sanitize({category={},message="m",symbol="s"}) == nil)
local merged = Payload.merge({clean}, {clean}, 10)
check("diagnostics sync does not duplicate entries", #merged == 1 and merged[1].count == 1)
check("scanner detects unfinished implementation", #StaticScan.scanSource("local x = 'not implemented'", "test") == 1)
print(string.format("%d regression checks, %d failures", total, failures))
assert(failures == 0, "Regression failures")
