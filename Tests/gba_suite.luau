--!nocheck
--[[ Tests/gba_suite.luau

 Runs the MIT-licensed jsmolka/gba-tests ROMs through the emulator headlessly.

 Each ROM executes its test battery at boot and then parks in an idle loop. On
 success it renders "All tests passed" and leaves IWRAM untouched. On failure it
 stores the failing test number as three decimal digits at 0x03000000, +4, +8.

 Run with:
     python3 tools/prepare_tests.py
     python3 tools/fetch_gba_tests.py
     luau build/Tests/gba_suite.luau
 ]]

local CREDIT = "Test ROMs: jsmolka/gba-tests, (c) 2019 Julian Smolka, MIT License"

local GBA = require("../Client/Emulator/GBA")
local Base64 = require("../Shared/Base64")

local ROMS = {
	"arm_arm", "thumb_thumb", "memory_memory", "bios_bios",
	"ppu_stripes", "ppu_hello", "ppu_shades",
	"save_sram", "save_none", "save_flash64", "save_flash128",
	"nes_nes", "unsafe_unsafe",
}

-- bios_bios asserts the exact contents of the real BIOS ROM at 0x00000000
-- (instruction words after reset, after a SWI, and during an IRQ). LuauGBA uses
-- high-level emulation and ships no BIOS image, so that ROM cannot pass by
-- design. It is reported separately rather than counted as a regression.
local EXPECTED_UNSUPPORTED = { bios_bios = "needs a real BIOS image (HLE only)" }

local FRAMES = 12
local passed, failed, errored, skipped = 0, 0, 0, 0

for _, name in ROMS do
	local ok, chunks = pcall(require, "../roms/" .. name)
	if not ok then
		print(string.format("  %-16s SKIP (module missing)", name))
		continue
	end

	local bytes = Base64.decodeToBuffer(table.concat(chunks))
	local gba = GBA.new({ rom = bytes })

	local okRun, err = pcall(function()
		for _ = 1, FRAMES do gba:runFrame() end
	end)

	if not okRun then
		errored += 1
		print(string.format("  %-16s ERROR  %s", name, tostring(err)))
		continue
	end

	-- Results live at 0x03000000 / +4 / +8. IWRAM is a 1-based array here.
	local iw = gba.bus.iwram
	local hundreds, tens, ones = iw[1] or 0, iw[5] or 0, iw[9] or 0
	local pc = gba.cpu.regs[16]

	if EXPECTED_UNSUPPORTED[name] then
		skipped += 1
		print(string.format("  %-16s N/A    %s", name, EXPECTED_UNSUPPORTED[name]))
		continue
	end

	if hundreds == 0 and tens == 0 and ones == 0 then
		passed += 1
		print(string.format("  %-16s PASS   (pc=0x%08X)", name, pc))
	else
		failed += 1
		local num = hundreds * 100 + tens * 10 + ones
		print(string.format("  %-16s FAIL   first failing test = %d", name, num))
	end

end

print(string.format("\n%d passed, %d failed, %d errored, %d not applicable", passed, failed, errored, skipped))
print(CREDIT)
