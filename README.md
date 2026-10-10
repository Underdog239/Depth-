# Depth / LuauGBA — testing build

A client-side Game Boy Advance emulator written in Luau for Roblox.
All runtime work stays on the client; no server scripts, remotes or DataStores
are used. Diagnostics reset when you leave the session.
Version **0.3.0-testing** provides a built-in interactive homebrew demo, ROM
loading, touch/keyboard/gamepad controls with session remapping, a responsive
menu, graphics, session snapshots, battery-save export/import, and health reports.
Device budgets adapt automatically; see [performance limits](docs/PERFORMANCE.md).

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
This command requires Studio's Command Bar in Edit mode. It creates the client
and its modules; it is not an in-game LocalScript loader. You can also
paste the full contents of `installer/Depth-install.luau` into the Command Bar
without enabling HTTP. The installer refuses to overwrite existing
`ReplicatedStorage.Assets`, `ReplicatedStorage.Shared`,
or `StarterPlayerScripts.GBAClient` objects.
Use a new Baseplate or move conflicting objects before installing.

If upgrading from the earlier installer, stop Play and remove its
`ServerScriptService.GBAServer` folder (and `ReplicatedStorage.GBADiagRemotes`
if present). Replace its `ReplicatedStorage.Shared`, `ReplicatedStorage.Assets`
and `StarterPlayerScripts.GBAClient` objects before installing again. Back up
custom configuration and `Assets.ROM` first. The installer does not remove old
objects automatically.

Rebuild the installer after changing source:

```bash
rojo build default.project.json -o Depth-testing.rbxlx
python3 tools/build_installer.py Depth-testing.rbxlx installer/Depth-install.luau
```

## Load a game

A Roblox client cannot open a local ROM file. Download `web/rom-tool.html`
from GitHub and open the downloaded file in your browser. Files stay local.

1. Choose a `.gba` file and press **Generate ROM.luau**.
2. Small files: **Copy base64**, then **Menu → Add a game → Load pasted ROM**.
3. Larger files: **Download Studio ROM installer**, stop Play and paste that
   downloaded script into Studio's Command Bar. Press Play to auto-load it.
4. Rojo users can instead save **Download ROM module** to `src/Assets/ROM.luau`
   and rebuild/sync. The module path supports up to 32 MiB. The in-game paste
   box is limited to 200,000 characters. Large ROM conversion/installation may
   take time; use Rojo if Studio cannot accept a very large paste.

Generated ROMs are ignored by Git. No game ROMs or Nintendo BIOS are bundled.

## Controls and saves

- `Z` / `X`: A / B; arrow keys: D-pad.
- `Enter`: Start; `RightShift`: Select; `A` / `C`: L / R.
- Touch controls appear automatically; use the menu to force them on/off.
- Gamepad D-pad/stick, A/B, Start/Select and shoulders work by default; **Y**
  opens the menu. Tap an action in **Menu → Controls** to remap keyboard or
  controller input. Remaps last for the session. Restore defaults is one tap.
- **Save state / Load state** capture and restore the current machine within
  the same session and cartridge. Loading another ROM clears the snapshot.
- **Export save / Import save** transfer battery-save bytes as base64. Copy
  exported text to a local file and paste it back in a later session with the
  same game loaded. Import restarts the game. Game saves are not automatically
  uploaded to DataStore.
- **Diagnostics** shows findings held in memory on this client. Findings are
  cleared when the session ends.

## Automated checks

Use standalone [Luau 0.742](https://github.com/luau-lang/luau/releases/tag/0.742)
and Python 3.9+. Wally dependencies are empty.

```bash
python3 tools/prepare_tests.py
luau build/Tests/run.luau
luau build/Tests/regressions.luau
luau build/Tests/client_features.luau
python3 tools/check_client_adapters.py
node tools/check_rom_tool.cjs
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

- **Full GBA audio is unavailable.** The optional uploaded-waveform adapter
  approximates two square channels. Without a permitted Roblox audio asset,
  playback is silent. [Audio setup and limits](docs/AUDIO.md).
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

See [background health/GitHub reports](docs/HEALTH.md), [architecture](docs/ARCHITECTURE.md), [audio](docs/AUDIO.md),
[performance](docs/PERFORMANCE.md), and [testing](docs/TESTING.md).

## Licence

MIT — see [LICENSE](LICENSE). No third-party source or game/BIOS images are
bundled. Public test fixtures are downloaded into ignored directories.
