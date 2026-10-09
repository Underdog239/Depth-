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
