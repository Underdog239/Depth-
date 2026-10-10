# Add a game to Depth

Depth uses **Game Boy Advance ROMs** (`.gba`), not Game Boy/DS/Switch files.
Start with **Run demo** to check your setup without finding a ROM. For your own
game, use a homebrew ROM or a backup you have permission to use. Extract ZIP
archives before choosing a file.

## Small launcher for large ROMs

If the embedded `Depth-game.luau` is too large to paste, use your loader's local
file support. This needs `readfile`, `game:HttpGet`, `loadstring` and Roblox buffers.
Ordinary Roblox LocalScripts cannot read device files.

1. In the helper, choose your `.gba` and click **Download Depth-ROM.gba**.
2. Move that file into your **script loader's workspace folder**, keeping the
   name `Depth-ROM.gba`. Downloading it alone does not move it into this folder.
   The workspace location depends on the loader; mobile file access may be limited.
3. Click **Copy small launcher**, rejoin Roblox and execute that short line first.

The launcher reads the raw ROM file directly. Its copied code stays the same size
regardless of the ROM size; no base64 expansion or game data is pasted into the
script editor. The game is still held in emulator memory, up to 32 MiB.
If `readfile` is unavailable, use your loader's **open/import script file** feature
for the existing embedded launcher, or the Studio/Rojo method below. A static
website cannot provide local file access to a loader that lacks it.

To use another workspace filename, call the launcher with that path:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Underdog239/Depth-/coderabbit/explain-code-limit/230c69a5/installer/Depth-file-launcher.luau"))("MyGame.gba")
```

## Client launcher — no Studio installation

1. Open your deployed GitHub Pages ROM helper (see [hosting setup](GITHUB_PAGES.md)),
   or download `web/rom-tool.html` from GitHub and open it in your browser.
   The same helper is supplied in Outputs.
2. Choose your `.gba` file and press **Generate**.
3. Press **Download client launcher**. Open `Depth-game.luau` as text.
4. Join a fresh Roblox session and run the **entire downloaded script** in your
   client loader. Run this first, before opening Depth separately. The game loads
   automatically; opening Library pauses gameplay while you browse.

The loader must support `game:HttpGet` and `loadstring`. The launcher downloads
Depth's current runtime from its published task branch on GitHub and passes the
ROM directly to it. No Studio flags, ModuleScript creation or `.Source` writes
are used on this path. Ordinary Roblox LocalScripts cannot use this HTTP loader;
use the Studio/Rojo method in your own experience instead.

Your ROM stays on your device. **Keep the generated launcher private**: it contains
the game data. The helper accepts up to 32 MiB, but large generated scripts may
exceed a loader's size/memory limits. Downloading/importing a game does not imply
that the emulator supports it. BIOS support is partial; game speed and audio have
known limits. If a game freezes, check Saves → Health report and try the demo.

## Tiny ROMs — paste into the existing session

Generate → **Copy base64** → Depth **Library** → paste into the ROM box →
**Load pasted ROM**. This accepts at most 200,000 base64 characters (150,000 ROM
bytes, about 146 KiB). Use the client launcher for larger files.

## Studio / Rojo

Expand **Studio / Rojo exports** in the helper:

- **Download Studio ROM installer:** stop Play, paste the downloaded script into
  Studio's Command Bar, then Play. It refuses to overwrite `Assets.ROM`.
- **Download ROM module:** save as `src/Assets/ROM.luau`; rebuild/sync with Rojo.

Large scripts may exceed Studio's Command Bar limits; use Rojo for those files.
A normal Roblox client cannot browse local files; mobile players can paste tiny
ROMs or play ROMs already included in their experience.

## Keep your progress

Before switching games, use **Saves → Export save** and copy the text to a file.
Load the same game before importing it. State snapshots last only for the current
session. For Studio installations, back up/remove the old `Assets.ROM` before
installing a new game. Never commit ROMs or generated game launchers to GitHub.

## Game detected, but screen is blank

ROM detection verifies file transfer/header parsing. To check display startup,
open Library and Run demo, then close the menu and let it produce a frame; the
demo should turn green. Watch **GBA frames** in the bottom line. Opening the menu
pauses emulation. If the demo works but your game stays blank, send the ROM title
and a screenshot showing PC/LCD/frame values and Saves → Health report. Some
games still depend on unimplemented BIOS/hardware behavior.
