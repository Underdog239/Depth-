# LuauGBA - a Game Boy Advance emulator for Roblox

A **client-side GBA emulator written in Luau**, with a self-running
diagnostics catcher, a control-remapping layer and aggressive optimizations.

```
roblox/                      rojo project (default.project.json)
  src/Client/
    init.client.luau         bootstrap: diag + emulator + render + input + UI
    Emulator/
      CPU/Arm7tdmi.luau      full ARM + THUMB interpreter, banking, exceptions
      Bus/MemoryBus.luau     memory map, IO routing, cycle counter
      Bus/Regions.luau       address decode + VRAM mirroring
      Hardware/              PPU, DMA, timers, interrupts, keypad
      Cart/Cartridge.luau    ROM header parsing, save-type detection
      Cart/HLEBIOS.luau      BIOS SWIs reimplemented (no copyrighted BIOS needed)
      Save/SaveState.luau    full machine snapshot / restore
    Render/                  EditableImage presentation (+ frame-grid fallback)
    Input/                   keyboard + gamepad mapping, fully remappable
    Optimize/                profiler + adaptive frame pacing
    UI/                      player shell + live diagnostics dashboard
    Diagnostics/             the background bug/vulnerability/unfinished catcher
  src/Server/                DataStore persistence for findings
  src/Shared/                config, logging, signals, base64, types
  Tests/run.luau             runnable test suite (39 checks)
  tools/                     test harness + homebrew ROM generator
```

## Getting a ROM in (the one real constraint)

A Roblox client cannot read local files, so ROM bytes have to be baked into the
place. The supported path is a **browser-side tool** that never uploads
anything:

1. Open `web/rom-tool.html` in any browser (no server, no signup, no hosting).
2. Drop your legally-owned ROM on it. It parses the header and shows title, game
   code and checksum status.
3. Download `ROM.luau` into `src/Assets/`.
4. `rojo serve`, press Play - the client auto-loads it on join.

`src/Assets/ROM.luau` is git-ignored on purpose. There is also an in-game base64
box for small homebrew ROMs; a multi-megabyte commercial ROM will not fit in a
TextBox.

## Quick start

1. Install [Rojo](https://rojo.space/) and sync this repo into a place:

   ```bash
   rojo serve default.project.json
   ```

2. Press **Play** in Studio. The client script boots the emulator, the renderer,
   the input layer and the **diagnostics catcher** automatically.
3. Paste a base64-encoded ROM into the in-game box and hit **Load ROM**.
4. Play with the keyboard (`Z`/`X` = A/B, arrows = D-pad, `A`/`C` = L/R,
   `Enter` = Start, `RightShift` = Select) or a gamepad.
5. Open **Diagnostics** any time to see everything the catcher found.

## Running the tests

The emulator core is written so it can run **outside Roblox**. A small harness
rewrites the Roblox requires and executes the pure modules under the standalone
Luau binary:

```bash
python3 tools/prepare_tests.py
luau build/Tests/run.luau
```

Output ends with `ALL TESTS PASSED` when the core is healthy. The suite covers
base64, the diagnostics classifier/store/static scanner, the memory bus, ARM and
THUMB instructions, the PPU, cartridge parsing and a full end-to-end ROM boot.

## Generating a test ROM (no copyrighted content)

```bash
python3 tools/make_test_rom.py test.gba
```

This emits an original homebrew ROM that switches the PPU to mode 3 and paints
the screen. Load it to verify rendering end to end. Use real commercial ROMs only
if you legally own them - nothing copyrighted is included in this repository.

## Diagnostics: what it catches, and how

The catcher runs in the background from the moment you join and classifies every
signal into one of four buckets:

| category | meaning | example |
|---|---|---|
| `error` | something actually threw | uncaught runtime error |
| `bug` | logically wrong behaviour | out-of-range PPU line, stall, NaN PC |
| `vulnerability` | security weakness | `loadstring`, unvalidated remote use |
| `unfinished` | stubbed / TODO code | placeholder paths, unimplemented opcodes |

It combines:

* **runtime hooks** - `ScriptContext.Error`, `LogService.MessageOut`, guarded
  entry points (`Diag.guard`) and the logger sink;
* **static scanning** - walks every script the emulator owns and flags
  TODO/FIXME/stub markers, `loadstring`, `getfenv`, unchecked remotes and more;
* **invariants** - cheap assertions registered by the client (PC in range, valid
  CPU mode, PPU line bounds, no NaN) checked on a timer;
* **watchdog** - flags any frame that stalls past a threshold;
* **profiler** - attributes frame time to emulate vs present.

Findings are de-duplicated, counted, given a suggested fix, and persisted (server
DataStore) so they survive a rejoin. Open the dashboard to read them - you never
have to run a script to see results.

See `docs/DIAGNOSTICS.md` for the full model.

## What v1.0 includes

* **Core**: ARM7TDMI (ARM + THUMB), memory bus, PPU modes 0-5 with sprites,
  windows and blending, DMA, timers, interrupts, keypad, HLE BIOS.
* **Saves**: SRAM, Flash (command state machine) and EEPROM (serial over DMA3),
  with save-state snapshot/restore.
* **Audio**: full APU register model, mixer and sample pipeline (see
  `docs/AUDIO.md` for the Roblox playback wall).
* **Diagnostics**: background catcher, static scanner, invariants, watchdog,
  live dashboard, cross-session persistence.
* **Tooling**: headless test harness (54 checks), homebrew ROM generator,
  browser ROM embedding tool.

## Honest performance notes

A GBA runs at **16.78 MHz** with a 59.7 Hz display. A pure-Luau interpreter
cannot sustain full speed for every title, so this project ships the levers that
actually matter: an optimised dispatch core, frame-skip, adaptive scaling, a
cycle budget per frame and a profiler that shows where time goes. See
`docs/PERFORMANCE.md` for measured expectations and tuning guidance.

## Legal

No ROMs or BIOS images are included. The emulator uses a **HLE BIOS**, so it can
boot commercial titles without shipping Nintendo's copyrighted BIOS; supply your
own `bios.bin` if you want cycle-exact BIOS behaviour.

## Credits

This project's own code is original. It uses and credits the following:

| Component | Author | Licence | Use |
|---|---|---|---|
| [jsmolka/gba-tests](https://github.com/jsmolka/gba-tests) | Julian Smolka (c) 2019 | MIT | ARM/THUMB/PPU/save conformance ROMs, fetched at test time |
| [luau](https://github.com/luau-lang/luau) | Luau contributors | MIT | standalone interpreter running the headless harness |
| [rojo](https://github.com/rojo-rbx/rojo) | Rojo contributors | MPL-2.0 | optional Studio sync (external tool) |
| [mgba-emu/suite](https://github.com/mgba-emu/suite) | mGBA contributors | MIT | planned GBA conformance coverage |
| [mooneye-gb](https://github.com/Gekkio/mooneye-gb) | Gekkio | MIT | planned GB/GBC conformance coverage |

**No ROMs and no BIOS images are included in this repository.** Commercial ROMs
are never bundled; the BIOS is a from-scratch high-level emulation so no
copyrighted BIOS image is needed. Third-party test ROMs are downloaded on demand
into git-ignored directories and carry their upstream attribution with them.

See [CREDITS.md](CREDITS.md) for the full notice, including pinned commits.
