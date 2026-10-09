# Loading ROMs

Roblox clients cannot read local files, so ROMs reach the emulator as bytes:

## 1. In-game (base64 paste)

Encode your legally-owned ROM and paste it into the box in the UI:

```bash
base64 -w0 myrom.gba > myrom.b64
```

Press **Load ROM**. The client decodes it and boots.

## 2. Programmatically

```lua
local GBA = require(script.Parent.Emulator.GBA)
local gba = GBA.new({ rom = romBytes })   -- romBytes = {number} of bytes
```

## 3. Test ROM

```bash
python3 tools/make_test_rom.py test.gba
```

An original homebrew ROM that paints the screen - the fastest way to confirm the
emulator, renderer and PPU all work.

## BIOS

By default a **HLE BIOS** is installed: SWIs are handled in Luau, so commercial
ROMs boot without Nintendo's copyrighted BIOS. To use a real BIOS instead:

```lua
local GBA = require(script.Parent.Emulator.GBA)
local gba = GBA.new({ rom = romBytes, bios = biosBytes })
```

## Saves

Save types (SRAM / Flash / EEPROM) are detected from the ROM header. The backing
store is exposed as `gba:saveBytes()` / `gba:loadSaveBytes(bytes)` for you to
persist wherever you like.

## Legal

Nothing copyrighted is included. Only load ROMs and BIOS images you are legally
entitled to use.
