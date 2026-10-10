# Depth / LuauGBA — testing build

A client-side Game Boy Advance emulator written in Luau for Roblox.
Version **0.2.0-testing** provides a built-in interactive homebrew demo, ROM
loading, keyboard/gamepad controls, graphics, session snapshots, battery-save
export/import, and a diagnostics dashboard.

## Start testing

With [Rojo 7.7.1](https://rojo.space/) installed:

```bash
rojo build default.project.json -o Depth-testing.rbxlx
```

Open the resulting place in Roblox Studio, press **Play**, then **Run demo**.
The screen should turn green. Hold `Z`, `X`, or an arrow key to change its
colour. The demo is original project code; no external ROM or BIOS is needed.

For live development, use `rojo serve default.project.json` and connect the
Rojo Studio plugin. See [the testing guide](docs/TESTING.md) for a full checklist.

## Install into an existing Studio place

Stop Play and open Studio's **Command Bar** from the View tab. Enable
**Allow HTTP Requests** in Game Settings → Security, then run:

```lua
assert(loadstring(game:GetService("HttpService"):GetAsync("https://raw.githubusercontent.com/Underdog239/Depth-/refs/heads/coderabbit/explain-code-limit/230c69a5/installer/Depth-install.luau")))()
```

Press **Play**, then **Run demo**, and save your place to keep the installation.
This command requires Studio's Command Bar in Edit mode. It creates the client,
server and shared modules; it is not an in-game LocalScript loader. You can also
paste the full contents of `installer/Depth-install.luau` into the Command Bar
without enabling HTTP. The installer refuses to overwrite existing
`ReplicatedStorage.Assets`, `ReplicatedStorage.Shared`,
`ServerScriptService.GBAServer`, or `StarterPlayerScripts.GBAClient` objects.
Use a new Baseplate or move conflicting objects before installing.

Rebuild the installer after changing source:

```bash
rojo build default.project.json -o Depth-testing.rbxlx
python3 tools/build_installer.py Depth-testing.rbxlx installer/Depth-install.luau
```

## Load a game

A Roblox client cannot open a local ROM file. Use the included browser tool:

1. Open `web/rom-tool.html` locally in a browser.
2. Select a ROM, generate its module, and download `ROM.luau` into `src/Assets/`.
3. Rebuild the place or sync through Rojo, then press Play. The ROM loads on join.

For small homebrew files, paste base64 into the in-game ROM box. The module
path supports ROMs up to 32 MiB; the paste box is limited to 200,000 characters.
Generated ROM modules are ignored by Git. No game ROMs or Nintendo BIOS are
included in the repository or testing place.

## Controls and saves

- `Z` / `X`: A / B; arrow keys: D-pad.
- `Enter`: Start; `RightShift`: Select; `A` / `C`: L / R.
- Gamepad face buttons, D-pad, left stick, Start/Select and shoulder buttons
  are mapped in `src/Shared/Config.luau`.
- **Save state / Load state** capture and restore the current machine within
  the same session and cartridge. Loading another ROM clears the snapshot.
- **Export save / Import save** transfer battery-save bytes as base64. Copy
  exported text to a local file and paste it back in a later session with the
  same game loaded. Import restarts the game. Game saves are not automatically
  uploaded to DataStore.
- **Diagnostics** shows runtime findings. Optional server persistence is scoped
  to each player and requires Roblox DataStore access.

## Automated checks

Use standalone [Luau 0.742](https://github.com/luau-lang/luau/releases/tag/0.742)
and Python 3.9+. Wally dependencies are empty.

```bash
python3 tools/prepare_tests.py
luau build/Tests/run.luau
luau build/Tests/regressions.luau
python3 tools/fetch_gba_tests.py
luau build/Tests/gba_suite.luau
```

The external MIT test ROMs are fetched at the commit pinned in the fetch tool.
The harness requires each ROM to reach its known completion address and checks
the preserved result register. Missing fixtures, errors and timeouts fail the
process. Three graphics ROMs are boot checks, not image-accuracy comparisons.
See [CREDITS.md](CREDITS.md) for attribution.

Validate the Studio module layout after a build:

```bash
python3 tools/check_project.py Depth-testing.rbxlx
```

## Current limits

This is a build for testing, with specific automated coverage rather than a
claim of general commercial-game compatibility.

- Audio samples and levels are available for inspection; **playback is silent**.
- BIOS high-level emulation is partial. Unsupported SWIs stop emulation with
  their number and PC in the error message.
- Hardware cycle timing, sound accuracy and advanced graphics need broader
  testing. The real-BIOS conformance test is not applicable to the HLE build.
- Performance varies. The client runs bounded emulation slices to stay
  responsive; a game may run slower than a real GBA.
- EditableImage requires the relevant Roblox permissions. A coarse grid
  renderer is used when allocation or image binding is unavailable.
- Runtime static scanning cannot read protected script source in a published
  Roblox client. The dashboard is not a comprehensive code or security audit.
- Roblox Studio execution must be checked in Studio; standalone tests and a
  successful Rojo build do not validate Roblox rendering or input APIs.

See [architecture](docs/ARCHITECTURE.md), [audio](docs/AUDIO.md),
[performance](docs/PERFORMANCE.md), and [testing](docs/TESTING.md).

## Licence

MIT — see [LICENSE](LICENSE). No third-party source or game/BIOS images are
bundled. Public test fixtures are downloaded into ignored directories.
