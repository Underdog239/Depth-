# Performance

## The budget

| quantity | value |
|---|---|
| CPU clock | 16.777216 MHz |
| cycles per frame | 280,896 |
| display | 59.7275 Hz, 240x160 |
| instructions/frame (typical) | 60k - 200k |

To hit 60 FPS you must execute roughly **16.8 M instructions per second**; for
30 FPS, **8.4 M/s**. Luau can reach that for simple dispatch, but a full
interpreter with memory modelling lands lower - which is why every lever below
exists.

## What is implemented

* single top-byte branch for memory region selection;
* local variable caching in hot loops, no closures in per-pixel paths;
* priority keys instead of per-pixel sorting for BG/OBJ composition;
* direct access to `bus.vram` / `bus.pal` / `bus.oam` from the PPU (no method
  call per pixel);
* scanline rendering (cost scales with visible pixels, not cycles);
* `table.create` for all buffers to avoid rehashing;
* a cycle budget per frame so a runaway ROM cannot freeze the client.

## Adaptive layer (`Optimize/Adaptive.luau`)

Measured FPS drives three responses, each hysteresis-guarded so it never
oscillates:

1. **native** - present every produced frame;
2. **catchup** - emulate every frame but present every other one;
3. **auto-scale** - drop the render scale (fewer pixels to upload).

## Profiler (`Optimize/Profiler.luau`)

The frame loop is split into `emulate` and `present` sections. The status line
shows both, so you can tell instantly whether you are CPU-bound (emulate high)
or upload-bound (present high).

## Tuning checklist

* If `emulate` dominates: lower `Config.CORE.maxCyclesPerFrame` (slow-motion
  instead of dropped frames), or enable `useBlockCache`.
* If `present` dominates: lower `Config.RENDER.scale` or switch to `adaptive`.
* If both are fine but FPS is low: you are likely limited by Roblox's own frame
  pacing - check with the profiler before changing anything.

## Realistic expectations

Simple 2D titles (puzzle, early platformers) are the best candidates. Heavy 3D
or mode-7 style titles will run below full speed; the adaptive layer keeps them
playable rather than frozen. Treat the numbers in the status line as ground
truth for your hardware, not the ones in any README.

## Measured numbers (v1.0, headless Luau harness)

These come from `Tests/run.luau` and a standalone benchmark, run against a
16 MiB ROM. They are real measurements, not estimates.

| metric | value |
|---|---|
| 16 MiB ROM as a `buffer` | 16,384 KiB - exactly the payload |
| 16 MiB ROM load (header parse + save backend) | ~4 ms, +128 KiB of Lua structures |
| 4 MiB ROM as a Lua array | 65,536 KiB (16.0 bytes per entry) |
| buffer vs array, same bytes | **16x smaller** |
| PPU render, full 160 scanlines, mode 0 | 3.5 ms/frame |
| PPU blit alone (38,400 pixels) | ~1.2 ms/frame (0.03 us per pixel) |
| CPU interpreter | ~70 ms/frame, **1.24 M instructions/sec** |

### The bottleneck is the CPU, not the renderer

The render pipeline was collapsed from three passes (PPU -> table -> 38,400
iteration Lua loop -> buffer) to two (PPU -> buffer -> GPU upload). That removed
roughly 150,000 operations per frame, and it was the right cleanup - but it
saved only a couple of milliseconds, because rendering was never the constraint.

The interpreter executes about **1.24 M instructions per second**. A GBA needs
roughly 6-11 M instructions per second for full speed, so the current core runs
at roughly 10-20% of real time. For a title that executes 90,000 instructions
per frame (a trivial loop), a frame costs ~73 ms - about 14 FPS. Simpler titles
with fewer instructions per frame do better; heavier ones worse.

### Where the remaining cost is

Per emulated instruction the core still pays for:

* method calls (`self:reg`, `self:setReg`, `self:readWord`, `bus:read32`);
* a region dispatch on every memory access;
* `bus:tick` fanning out to three components every instruction.

Optimisations already applied: direct ROM paths in `read16`/`read32` (the
hottest region - every fetch), inlined interrupt polling in `CPU:step`, and
`bit32.band` instead of `%` for address masking. Together these cut frame time
from 110 ms to 73 ms (~34%).

### What would actually close the gap

The remaining work is interpreter engineering, not rendering:

1. Cache the decoded register file and the memory-region tag in locals.
2. Batch `bus:tick` instead of ticking three components per instruction.
3. A decoded-instruction cache or basic-block cache keyed on PC.
4. Only then consider parallel Luau (`task.desynchronize` inside an `Actor`) -
   and note the CPU must stay on the main thread, so the win there is limited.

Until those land, treat 30+ FPS as a target for light titles, and use the
adaptive layer plus `Config.CORE.maxCyclesPerFrame` to keep heavier ones
playable rather than frozen.

### Round 2: interpreter hot-path work (measured)

Attribution before the changes (per emulated instruction):

| stage | cost | share |
|---|---|---|
| `cpu:step` (decode + execute + fetch) | 0.405 us | 51% |
| `bus:tick` (PPU + timers + APU) | 0.295 us | 38% |
| of which `timers:tick` | 0.104 us | |
| of which `ppu:tick` | 0.097 us | |

Applied:

1. **Tick batching** - cycles are accumulated and flushed every 4 instructions
   instead of ticking three components per instruction.
2. **bit32 localised** at the top of the CPU, bus and PPU modules.
3. **Register access de-methodised** - `self:reg()` / `self:setReg()` became plain
   `getReg(cpu, i)` / `putReg(cpu, i, v)` functions, removing a metatable lookup
   from every call.

Result:

| metric | before | after |
|---|---|---|
| us per instruction | 0.786 | 0.660 |
| instructions/sec | 1.24 M | **1.51 M** |
| frame (90k-instruction workload) | 73.3 ms | **59.5 ms** |

New profile: `cpu:step` is now **62%** of an instruction; the batched tick is
~11%. The bottleneck has moved into the decoder itself.
