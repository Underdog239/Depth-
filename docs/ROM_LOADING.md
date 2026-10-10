# Easy ROM loading

Download `web/rom-tool.html` from the repository and open it in a browser.
Select a `.gba` ROM, then Generate. The file never leaves your browser.

- **Small ROM:** Copy base64 → Depth Menu → Add a game → Load pasted ROM.
- **Larger ROM in Studio:** Download Studio ROM installer. Stop Play, open the
  downloaded script, paste it into Studio's Command Bar, then Play. No Rojo
  setup is needed. The installer refuses to overwrite an existing Assets.ROM.
- **Rojo:** Download ROM module as `src/Assets/ROM.luau`; rebuild/sync.

Use ROMs you can legally use. Nothing is uploaded by the helper. A normal
Roblox client cannot open device files or fetch arbitrary HTTP ROM URLs.
Mobile players receive ROM assets already embedded in the place or can paste
small base64 ROMs; installing larger ROMs requires desktop Roblox Studio.

The maximum embedded ROM is 32 MiB; the paste box accepts 200,000 characters.
Large scripts may exceed practical Studio Command Bar limits; use the Rojo
module workflow when that happens. Header checksum warnings are reported but
are not a guarantee of compatibility. BIOS support is partial.

Before replacing a game, export its battery save through the Menu and keep the
text in a file. Stop Play and back up/remove the old Assets.ROM before installing
a new one. Import save text only after loading the same game; matching byte
length alone does not identify the game. State snapshots stay within a session.
