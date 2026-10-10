# Loading ROMs

Roblox clients cannot read local files, so ROMs reach the emulator as bytes:

## 1. In-game (base64 paste)

Encode your legally-owned ROM and paste it into the box in the UI:

```bash
base64 -w0 myrom.gba > myrom.b64
```

Press **Load ROM**. The client decodes it and boots. The paste box is limited
to 200,000 characters. For larger files, use `web/rom-tool.html` to generate
`src/Assets/ROM.luau`, then rebuild or sync through Rojo.

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

By default a partial **HLE BIOS** handles selected SWIs in Luau. Unsupported
calls stop with a diagnostic error; game compatibility varies. The core also
accepts an optional BIOS byte array, but that path has not been validated in
this testing build:

```lua
local GBA = require(script.Parent.Emulator.GBA)
local gba = GBA.new({ rom = romBytes, bios = biosBytes })
```

## Saves

Save types (SRAM / Flash / EEPROM) are detected from signatures in the ROM
with a small game-code fallback table. The backing
store is exposed as `gba:saveBytes()` / `gba:loadSaveBytes(bytes)` for you to
persist wherever you like.

## Legal

Nothing copyrighted is included. Only load ROMs and BIOS images you are legally
entitled to use.
