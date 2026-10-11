# Depth / LuauGBA — testing build nameer

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

## Run as one client script

`installer/Depth-runtime.luau` contains the whole client as ordinary Luau
functions. Paste its full contents into **one LocalScript in
StarterPlayerScripts**, then Play or publish your own experience. It runs in
both Studio play sessions and published Roblox clients. No separate Shared
modules or script `.Source` writes are required; small ROM paste/demo work
immediately, and an existing `ReplicatedStorage.Assets.ROM` is still supported.

The runtime checks for `Players.LocalPlayer` and waits up to 10 seconds for
`PlayerGui`. Neither entry point checks Studio, running-mode or client-mode flags.
It requires Roblox client services. It is not
portable to plain Lua, Roblox servers or a browser. It does not enable HTTP or
`loadstring` in ordinary LocalScripts; use the full source as the LocalScript.
Source diagnostics use the bundled repository report because individual module
Instances no longer exist. Running it again preserves the existing session.

`Depth-install.luau` starts the same bundled runtime whenever `LocalPlayer` is
available. Otherwise it attempts to install the normal module hierarchy, which
requires script `.Source` permissions (normally Studio's Edit-mode Command Bar).
Use `Depth-runtime.luau` for direct client execution.

## Gold interface and your own games

The client has a charcoal/gold theme with **Library, Controls, Settings and Saves**
tabs. Keyboard, touch and controller input still switch automatically. Styling
uses native UI objects and static gradients; it adds no animation/render loop.

For a ROM without Studio: download and open `web/rom-tool.html`, choose your `.gba`,
click **Generate → Download client launcher**, then run the downloaded script in a
fresh Roblox client session with HTTP/loadstring support. Your ROM is included
locally and auto-loads. See [the ROM guide](docs/ROM_LOADING.md) for exact steps,
small-ROM paste, Studio alternatives and save export.

## Install into an existing Studio place

Stop Play and open Studio's **Command Bar** from the View tab. Enable
**Allow HTTP Requests** in Game Settings → Security, then run:

```lua
assert(loadstring(game:GetService("HttpService"):GetAsync("https://raw.githubusercontent.com/Underdog239/Depth-/refs/heads/coderabbit/explain-code-limit/230c69a5/installer/Depth-install.luau")))()
```

Press **Play**, then **Run demo**, and save your place to keep the installation.
This HTTP command is for Studio's Command Bar in Edit mode. It installs the
client and its modules. For direct client execution, use the runtime above. You can also
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
python3 tools/build_runtime.py Depth-testing.rbxlx installer/Depth-runtime.luau
```

## Host the ROM helper on GitHub

A GitHub Pages workflow is included. A repository administrator enables
**Settings → Pages → Source: GitHub Actions**, then re-runs the Pages deployment.
See [hosting setup and ROM privacy](docs/GITHUB_PAGES.md). Each visitor's ROM stays
in their own browser; the website needs no user accounts or shared ROM storage.

## Load a game

A Roblox client cannot open a local ROM file. Download `web/rom-tool.html`
from GitHub and open the downloaded file in your browser. Files stay local.

1. Choose a `.gba` file and press **Generate**.
2. **Download client launcher**, open it as text and run its full contents in a
   fresh client session with HTTP/loadstring support. It auto-loads your ROM.
3. Tiny files: **Copy base64**, then **Library → Load pasted ROM**.
4. Studio/Rojo users can expand the helper's export options. See
   [ROM loading](docs/ROM_LOADING.md) for installation and troubleshooting.

If the embedded script is too large to paste, use **Copy small launcher** with
`Depth-ROM.gba` in your loader's workspace. This requires `readfile`; see the ROM
guide for folder setup and alternatives.

The helper supports up to 32 MiB; your loader may impose a smaller limit. The
in-game paste box is limited to 200,000 base64 characters.

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
