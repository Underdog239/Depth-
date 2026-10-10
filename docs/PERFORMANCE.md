# Performance and device testing

## Responsiveness policy

The interpreter does a bounded amount of work per Roblox render callback:

- Touch-capable devices start at **4 ms** per slice; desktop starts at **8 ms**.
- Sustained slow host frames lower the budget toward **2 ms** and present every
  second emulated frame. Stable fast frames recover the budget gradually.
- **Battery saver** caps work at 3 ms and reduces presentation frequency.
- Opening the menu or losing focus suspends emulation and releases input.
- Clock checks occur every 256 instructions. A single instruction or hardware
  update can exceed the requested budget; it is not a hard real-time deadline.

These settings prioritise responsive controls. Slower devices run the emulated
game more slowly. They do **not** promise full-speed GBA gameplay on midrange
phones or PCs. No real device benchmark has been completed in this sandbox.

## Reduced overhead

Audio batch draining now moves arrays in bulk instead of shifting the remaining
array for every sample. Controller stick input is event driven. Diagnostics
checks invariants every 10 seconds and probes protected source only once;
source findings are bundled at build time. The hidden dashboard does no row
rebuilding, and visible updates are capped at once per second / latest 60 rows.

EditableImage uploads the native 240×160 buffer. The fallback is a coarse
40×26 grid, capped at 20 presentations/second, with unchanged cell colours
skipped. Display scaling fits the viewport; it does not reduce interpreter or
native framebuffer work. ROMs remain buffers, not multi-megabyte Lua arrays.

## Reproducible sandbox probe

```bash
python3 tools/prepare_tests.py
luau build/Tests/performance.luau
```

On this Amazon Linux sandbox using standalone Luau 0.742, the original demo
produced these results on 2026-10-10:

| Requested budget | Mean slice | p95 | Maximum | Emulated frames / 90 slices |
|---|---:|---:|---:|---:|
| 4 ms | 4.09 ms | 4.26 ms | 4.27 ms | 3 |
| 8 ms | 8.00 ms | 8.22 ms | 8.24 ms | 5 |

The measured game throughput is well below full speed. Slicing prevents one
whole emulated frame from occupying a long UI callback; it does not make CPU
emulation faster. These numbers exclude Roblox rendering/audio and cannot be
used to certify phone performance.

## Before calling a device supported

Test an actual midrange Android phone, an iPad/tablet and a PC for at least ten
minutes with representative permitted homebrew. Record device/OS, ROM, UI FPS,
emulation speed, peak slice time, renderer, heat and battery impact. Test
portrait/landscape, touch multi-press, controller reconnect, menu transitions,
background/resume and save/import. The metrics UI reports host frame time and
work budget, not an assertion of emulated game FPS.
