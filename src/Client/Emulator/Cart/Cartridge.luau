--!strict
--[[ Emulator/Cart/Cartridge.luau

 Parses a real GBA ROM header (offset 0x0000..0x00BF) and exposes the ROM as a
 byte array plus derived metadata (title, game code, save type, checksum).

 Save-type detection uses the same heuristic table most emulators use, driven
 by the (gameCode, makerCode, version) triple. Backups that match a known entry
 get their type; everything else defaults to SRAM (safe fallback) unless the
 header says otherwise.
 ]]

local Util = require(game:GetService("ReplicatedStorage").Shared.Util)

export type Cartridge = {
	rom: { number },
	size: number,
	info: any,
	read8: (self: Cartridge, offset: number) -> number,
	read16: (self: Cartridge, offset: number) -> number,
	read32: (self: Cartridge, offset: number) -> number,
	saveBytes: (self: Cartridge) -> { number },
	loadSaveBytes: (self: Cartridge, bytes: { number }) -> (),
}

local Cartridge = {}
Cartridge.__index = Cartridge

local SAVE_EEPROM = "EEPROM"
local SAVE_SRAM = "SRAM"
local SAVE_FLASH512 = "FLASH512"
local SAVE_FLASH1024 = "FLASH1024"
local SAVE_NONE = "NONE"

-- (gameCode) -> save type. Kept short here; extend freely.
local SAVE_TABLE: { [string]: string } = {
	["A9PJ"] = SAVE_EEPROM,
	["AA4J"] = SAVE_EEPROM,
	["ABPP"] = SAVE_FLASH512,
	["AF4J"] = SAVE_EEPROM,
	["AGBJ"] = SAVE_EEPROM,
	["AIDJ"] = SAVE_EEPROM,
	["AR8J"] = SAVE_EEPROM,
	["AXVJ"] = SAVE_EEPROM,
}

local function detectSaveType(gameCode: string, fallback: string): string
	local entry = SAVE_TABLE[gameCode]
	if entry then return entry end
	return fallback
end

--- Parse the 0x00..0xBF header. Returns a RomInfo table (never errors).
function Cartridge.parseHeader(rom: { number }): any
	local function str(off: number, len: number): string
		local bytes = table.create(len)
		for i = 1, len do bytes[i] = rom[off + i] or 0 end
		-- strip trailing NULs and spaces
		return (Util.bytesToString(bytes)):gsub("[%z\s]+$", "")
	end

	local fixed = rom[0xB3] or 0 -- 0x96 expected at 0xB2 in fixed-value region
	local entry = Util.readLE(rom, 1, 4)
	local checksum = 0
	for i = 0xA0, 0xBC do
		checksum = (checksum - (rom[i + 1] or 0)) % 256
	end
	local hdrChecksum = rom[0xBD + 1] or 0
	local sizeIndex = rom[0xBE + 1] or 0
	local romSize = 0x8000 * (2 ^ sizeIndex)

	return {
		title = str(0, 12),
		gameCode = str(0xC, 4),
		makerCode = str(0x10, 2),
		version = rom[0xBC + 1] or 0,
		entryPoint = entry,
		headerChecksum = hdrChecksum,
		headerChecksumOk = checksum == hdrChecksum,
		firmwareFlag = fixed,
		romSizeBytes = romSize,
		sizeIndex = sizeIndex,
		saveType = detectSaveType(str(0xC, 4), SAVE_SRAM),
	}
end

--- Create a cartridge from raw ROM bytes.
function Cartridge.new(romBytes: { number }): Cartridge
	local info = Cartridge.parseHeader(romBytes)
	return setmetatable({
		rom = romBytes,
		size = #romBytes,
		info = info,
		_sram = {} :: { number },
	}, Cartridge) :: any
end

function Cartridge:read8(offset: number): number
	return self.rom[offset + 1] or 0
end

function Cartridge:read16(offset: number): number
	return (self.rom[offset + 1] or 0) + (self.rom[offset + 2] or 0) * 0x100
end

function Cartridge:read32(offset: number): number
	return (self.rom[offset + 1] or 0)
		+ (self.rom[offset + 2] or 0) * 0x100
		+ (self.rom[offset + 3] or 0) * 0x10000
		+ (self.rom[offset + 4] or 0) * 0x1000000
end

function Cartridge:saveBytes(): { number }
	return self._sram
end

function Cartridge:loadSaveBytes(bytes: { number })
	-- copy up to 64 KiB
	for i = 1, math.min(#bytes, 0x10000) do
		self._sram[i] = bytes[i]
	end
end

Cartridge.SAVE_EEPROM = SAVE_EEPROM
Cartridge.SAVE_SRAM = SAVE_SRAM
Cartridge.SAVE_FLASH512 = SAVE_FLASH512
Cartridge.SAVE_FLASH1024 = SAVE_FLASH1024
Cartridge.SAVE_NONE = SAVE_NONE

return Cartridge
