# Architecture

```
                 +-------------------------------+
   init.client   |  Diagnostics (background)     |  hooks, static scan,
        |        |  classifier -> store -> UI    |  invariants, watchdog
        v        +-------------------------------+
   +---------+    +---------+    +-------------+
   |  Input  | -> |   GBA   | -> |  Renderer   |
   | mapping |    |  core   |    | EditableImg |
   +---------+    +----+----+    +-------------+
                       |
        +--------------+--------------+
        v              v              v
   Arm7tdmi        MemoryBus        PPU/DMA/
   (ARM+THUMB)     (regions, IO)    timers/keypad
```

## Layering rules

1. **`Shared/`** never depends on `Client/` or `Server/`. It holds config, the
   logger, signals, base64 and shared types.
2. **`Emulator/`** is Roblox-independent apart from `ReplicatedStorage.Shared.Config`.
   Every module under it can run under the standalone Luau binary (that is how the
   test suite works).
3. **`Render/`, `Input/`, `UI/`** are the only Roblox-facing layers. They never
   reach into emulator internals beyond the documented `GBA` API.
4. **`Diagnostics/`** is passive: it observes. Nothing in the emulator depends on
   diagnostics for correctness, so a failure there can never break emulation.

## The emulator core

### CPU (`Arm7tdmi.luau`)

* Registers live in a 1-based array `regs[1..16]` (`regs[16]` = R15/PC).
* Register numbers are 0-based in the decoder; `reg()`/`setReg()` translate and
  apply the PC pipeline offset (+8 ARM, +4 THUMB).
* Banked registers are swapped on mode changes (`_setMode`), including FIQ's
  R8-R12 and each exception mode's SPSR.
* Decode order matters and mirrors the ARM ARM: multiply/swap/halfword first,
  then data processing, then the second-half decoder (`executeARM2`) for
  load/store, block transfer, branches and PSR transfers.
* THUMB implements all 19 formats in `executeTHUMB`.

### Bus (`MemoryBus.luau`)

* One top-byte branch selects the region, tuned for the interpreter hot path.
* IO is routed to components by offset range (PPU, sound, DMA, timers, keypad,
  interrupts); unmapped IO falls back to a backing array.
* VRAM is 96 KiB - not a power of two - so `Regions.vramOffset` implements the
  real mirroring rather than a mask.
* `tick(cycles)` advances the PPU and timers; DMA adds stall cycles.

### PPU (`Ppu.luau`)

Scanline based. For each visible line it:

1. computes window masks (WIN0/WIN1/OBJ window/outside),
2. draws sprites (collecting the OBJ window) with a combined priority key so BG
   vs OBJ vs OBJ-index ordering matches hardware,
3. draws backgrounds for the active display mode (0-5),
4. applies alpha blending / brighten / darken,
5. blits the RGB15 line to a packed RGBA buffer.

### Cartridge + HLE BIOS

`Cartridge` parses the real header (title at 0xA0, code at 0xAC, checksum at
0xBD, size at 0xBE) and detects the save type. `HLEBIOS` reimplements the BIOS
SWIs (Div, Sqrt, CpuSet, LZ77/RL, Halt, VBlankIntrWait, ...) so commercial ROMs
boot without a copyrighted BIOS image.

## Determinism

Given the same ROM, the same input sequence and the same cycle budget, the core
produces the same frames. That is what makes the test suite and the diagnostics
invariants meaningful.
