--!nocheck
-- Completion addresses refer to the MIT jsmolka/gba-tests commit pinned by
-- tools/fetch_gba_tests.py. Each is the unique ARM B-to-self after evaluation.
local GBA = require("../Client/Emulator/GBA")
local Base64 = require("../Shared/Base64")
local ROMS = {
 {"arm_arm", 0x08001EC4}, {"thumb_thumb", 0x08000AAC},
 {"memory_memory", 0x080004C8}, {"save_sram", 0x08000470},
 {"save_none", 0x080002A8}, {"save_flash64", 0x08000AC8},
 {"save_flash128", 0x08000C4C},
 -- These are visual smoke tests: completion proves boot, not pixel accuracy.
 {"ppu_stripes", 0x08000140, true}, {"ppu_hello", 0x08000160, true},
 {"ppu_shades", 0x0800015C, true},
}
local passed, failed = 0, 0
for _, spec in ROMS do
 local name, done, visual = unpack(spec)
 local ok, err = pcall(function()
  local bytes = Base64.decodeToBuffer(table.concat(require("../roms/" .. name)))
  assert(buffer.readu32(bytes, done - 0x08000000) == 0xEAFFFFFE, "fixture completion marker mismatch")
  local gba = GBA.new({rom = bytes})
  local completed = false
  for _ = 1, 60 do
   gba:runFrame()
   if not gba.cpu.thumb and gba.cpu.regs[16] == done then completed = true; break end
  end
  assert(completed, string.format("did not finish (pc=0x%08X)", gba.cpu.regs[16]))
  if not visual then
   -- m_test_eval preserves the result register; memory tests also use IWRAM.
   local failure = gba.cpu.regs[name == "thumb_thumb" and 8 or 13]
   assert(failure == 0, "first failing test = " .. failure)
  end
 end)
 if ok then passed += 1; print(name .. (visual and " BOOT PASS" or " PASS"))
 else failed += 1; print(name .. " FAIL: " .. tostring(err)) end
end
print(string.format("%d passed, %d failed", passed, failed))
print("BIOS suite requires a real BIOS; NES/unsafe demos have no conformance result protocol and are excluded.")
print("Test ROMs: jsmolka/gba-tests, (c) 2019 Julian Smolka, MIT License")
assert(failed == 0, string.format("%d conformance/boot checks failed", failed))
