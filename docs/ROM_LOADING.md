# Add a game to Depth

Depth uses **Game Boy Advance ROMs** (`.gba`), not Game Boy/DS/Switch files.
Start with **Run demo** to check your setup without finding a ROM. For your own
game, use a homebrew ROM or a backup you have permission to use. Extract ZIP
archives before choosing a file.

## Client launcher — no Studio installation

1. Download `web/rom-tool.html` from GitHub (Download raw file), then open the
   downloaded HTML file in your browser. The same helper is supplied in Outputs.
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
