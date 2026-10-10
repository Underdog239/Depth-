# Credits and third-party notices

LuauGBA's own source (everything under `src/`, `Tests/`, `tools/`, `web/`) is
original work. It depends on the following third-party projects, and this file
records their licences and attribution as those licences require.

## Test suites

### jsmolka/gba-tests - MIT

* **Author:** Julian Smolka (Copyright (c) 2019)
* **Source:** https://github.com/jsmolka/gba-tests
* **Pinned commit:** `a7113b67e63f83a9b321696ddd7042ccfad6c881` (2025-04-19)
* **Used for:** ARM / THUMB / memory / PPU / save conformance ROMs, driven by
  `Tests/gba_suite.luau`.

These ROMs are **fetched at test time** by `tools/fetch_gba_tests.py` into
`.tools/` and `build/`, both of which are git-ignored. This repository does not
vendor or redistribute them. Run the fetch script to obtain your own copy; the
upstream `LICENSE` is reproduced into `build/roms/NOTICE.txt` when you do.

### mgba-emu/suite - MIT

* **Source:** https://github.com/mgba-emu/suite
* **Used for:** planned GBA hardware conformance coverage beyond the above.

### mooneye-gb - MIT (planned)

* **Source:** https://github.com/Gekkio/mooneye-gb
* **Used for:** planned Game Boy / Game Boy Color CPU and timing conformance.

## Tooling

### Luau - MIT

* **Source:** https://github.com/luau-lang/luau
* **Used for:** the standalone `luau` / `luau-analyze` binaries that run the
  headless test harness. Downloaded by the developer, never committed here.

### Rojo - MPL-2.0

* **Source:** https://github.com/rojo-rbx/rojo
* **Used for:** optional syncing of this project into Roblox Studio. Invoked as
  an external tool; no Rojo code is included in this repository.

## Game data

No ROM images and no BIOS images are included in this repository, in any form,
committed or otherwise.

* Commercial ROMs: **not included and never will be.** Supply your own.
* BIOS: not included. The emulator uses a **high-level emulation** BIOS written
  from scratch (`src/Client/Emulator/Cart/HLEBIOS.luau`) so that no copyrighted
  BIOS image is required.
* The test ROM produced by `tools/make_test_rom.py` is **original**, written for
  this project, and is freely redistributable.

If you add a third-party component, add it here with its licence and source at
the same time.
