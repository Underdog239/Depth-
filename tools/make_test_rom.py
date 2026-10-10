#!/usr/bin/env python3
"""Generate a tiny, original homebrew GBA ROM that proves the emulator works:
it switches the PPU to mode 3 and fills the screen with a solid colour, then
spins forever. No copyrighted content is involved.

Usage: python3 tools/make_test_rom.py [out.gba] [--rgb R G B]
"""
import struct, sys, os


def rgb15(r, g, b):
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def build(color15):
    # Real GBA ROMs keep the header in 0x00..0xBF; the entry point at 0x00 is an
    # ARM branch into the actual code, which lives from 0xC0 onwards.
    code = []
    code.append(0xE59F0020)  # LDR r0,[pc,#0x20]  -> 0x04000000 DISPCNT
    code.append(0xE59F1020)  # LDR r1,[pc,#0x20]  -> 0x0403 (mode 3 + BG2)
    code.append(0xE5801000)  # STR r1,[r0]
    code.append(0xE59F201C)  # LDR r2,[pc,#0x1C]  -> 0x06000000 VRAM
    code.append(0xE59F301C)  # LDR r3,[pc,#0x1C]  -> colour
    code.append(0xE59F401C)  # LDR r4,[pc,#0x1C]  -> 240*160 pixels
    code.append(0xE0C230B2)  # loop: STRH r3,[r2],#2
    code.append(0xE2544001)  # SUBS r4,r4,#1
    code.append(0x1AFFFFFC)  # BNE loop
    code.append(0xEAFFFFFE)  # B .
    pool = [0x04000000, 0x00000403, 0x06000000, color15, 240 * 160]

    blob = bytearray(0x1000)
    # entry point: B 0xC0  ->  offset = (0xC0 - 0x08)/4 = 0x2E
    struct.pack_into("<I", blob, 0x00, 0xEA00002E)
    for i, word in enumerate(code):
        struct.pack_into("<I", blob, 0xC0 + i * 4, word)
    for i, word in enumerate(pool):
        struct.pack_into("<I", blob, 0xC0 + len(code) * 4 + i * 4, word)

    # header fields
    title = b"LUAUGBATEST"
    blob[0xA0:0xA0 + len(title)] = title
    blob[0xAC:0xB0] = b"LTST"
    blob[0xB0:0xB2] = b"01"
    blob[0xB2] = 0x96
    blob[0xB3] = 0x00
    blob[0xBC] = 0x00
    blob[0xBE] = 0x00
    chk = -0x19
    for i in range(0xA0, 0xBD):
        chk = (chk - blob[i]) & 0xFF
    blob[0xBD] = chk

    total = bytearray(0x8000)
    total[0:len(blob)] = blob
    return bytes(total)


if __name__ == "__main__":
    out = "test.gba"
    color = rgb15(30, 200, 90)
    args = sys.argv[1:]
    if args and not args[0].startswith("--"):
        out = args[0]
    if "--rgb" in args:
        i = args.index("--rgb")
        r, g, b = (int(x) for x in args[i + 1:i + 4])
        color = rgb15(r, g, b)
    data = build(color)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out} ({len(data)} bytes, colour=0x{color:04X})")
