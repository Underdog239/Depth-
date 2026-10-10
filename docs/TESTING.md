# Testing Depth 0.3.0

## Fastest path

Open `Depth-testing.rbxlx` in Roblox Studio and press **Play** (F5).
Click **Run demo**. You can also build this place from source using:

```bash
rojo build default.project.json -o Depth-testing.rbxlx
```

The original demo needs no network, game ROM, BIOS or audio asset. The UI
reports the renderer in its metrics line (`editableimage` or `grid`).

## Studio acceptance checklist

These checks require Roblox Studio and remain manual acceptance gates.

1. **Startup:** panel and screen appear; Output has no module lookup errors.
2. **Display:** Run demo fills the screen green. Test `Config.RENDER.mode =
   "grid"` as well as the default EditableImage path. Grid output is coarse.
3. **Input:** hold Z, X and arrows. Colour changes; releasing returns to green.
   Repeat with a gamepad. Moving its left stick up must press GBA Up.
4. **Pause:** Pause freezes the screen; Play resumes. Test Reset while paused.
5. **Snapshot:** save a state, change input and run, pause, then load the state.
   The saved image should return immediately. Resume and verify continued play.
   A snapshot should not load after replacing the ROM.
6. **ROM import:** add `Assets.ROM` with the browser tool, rebuild and verify
   automatic loading. Also check a small base64 ROM and malformed input. The
   status should show an error for malformed data without terminating the UI.
7. **Battery save:** with a game that saves progress, export its save text to a
   file. Stop Play, restart, load the same game and import the saved text. Import
   restarts the game; progress should be restored. Export before loading another
   ROM or leaving. Import validates size, so always use the same game's save.
8. **Diagnostics:** open the dashboard, check reported issues, and verify that
   one error does not generate an endless stream of recursive findings.
9. **Client isolation:** verify there is no `GBAServer` script or
   `GBADiagRemotes` folder. With two clients, each demo, input, snapshot and
   diagnostics list must operate independently. Rejoining clears diagnostics.
   No Studio API access is needed; game saves use manual export/import.
10. **Responsiveness:** try a heavier homebrew ROM. UI controls should respond
    between emulation slices. Record renderer, game code and metrics when
    reporting a stall or graphical problem.

11. **Mobile:** test portrait and landscape at phone/tablet sizes; hold two
    touch buttons together, release each independently, switch focus and return.
12. **Remapping:** select A/B in Menu → Controls, press a new keyboard/controller
    button, and test it. Check timeout, cancellation and Restore defaults. Typing
    into ROM/save boxes must not move the game.
13. **Audio:** follow docs/AUDIO.md, upload the supplied original waveform with
    experience permission, enter its ID and press Test tone. Verify mute,
    pause/background silence and playback of a square-channel ROM. Wave/noise/
    FIFO music is not played by this adapter. Missing assets must be reported.
14. **Health:** check the three bundled known limits, source hash and fresh scan
    count. Confirm idle/hidden dashboards do not continuously rebuild rows.
15. **Performance:** follow the ten-minute real-device checklist in
    docs/PERFORMANCE.md. Automated passes do not certify midrange support.

16. **Standalone runtime:** use a fresh place with only a LocalScript containing
    Depth-runtime.luau. Verify no Shared folder is needed. Run demo, open menus,
    test touch/controller/ROM paste and diagnostics. In a published client,
    verify the same startup. Re-running keeps one UI/session. Roblox server
    execution is intentionally unsupported. Actual Studio/published-device
    acceptance remains outstanding; mocks only cover the runtime path.

## Automated verification

Validated tooling for this branch: Python 3.9.25, Luau 0.742 and Rojo 7.7.1.

```bash
python3 tools/prepare_tests.py
luau build/Tests/run.luau
luau build/Tests/regressions.luau
luau build/Tests/client_features.luau
python3 tools/check_client_adapters.py
node tools/check_rom_tool.cjs
python3 tools/scan_health.py --output health --module src/Shared/BuildReport.luau
python3 tools/fetch_gba_tests.py
luau build/Tests/gba_suite.luau
rojo build default.project.json -o Depth-testing.rbxlx
python3 tools/check_project.py Depth-testing.rbxlx
python3 tools/build_installer.py Depth-testing.rbxlx installer/Depth-install.luau
python3 tools/check_installer.py Depth-testing.rbxlx installer/Depth-install.luau
python3 tools/build_runtime.py Depth-testing.rbxlx installer/Depth-runtime.luau
python3 tools/check_runtime.py Depth-testing.rbxlx installer/Depth-runtime.luau installer/Depth-install.luau
```

`check_project.py` checks static module references and rejects server scripts,
remotes and server API calls. `check_installer.py` compares all installed
instances and source text to the built place using simulated Studio services;
it also exercises collision guards and failure cleanup. Actual Studio behavior
still requires the checklist above.

`prepare_tests.py` regenerates `build/`; run the fixture fetch **after** it.
The conformance fixtures are pinned to
`a7113b67e63f83a9b321696ddd7042ccfad6c881`. The fetch tool checks out that commit;
use its checkout only for test fixtures, not unrelated work.

The conformance gate covers ARM, THUMB, memory, SRAM, no-save, Flash64 and
Flash128. PPU stripes, hello and shades are separate boot smoke checks. Passing
means the expected completion loop was reached and the result register reports
success; it does not establish full game compatibility or graphical accuracy.
The real-BIOS suite and NES/unsafe demos are not conformance gates.

Regression checks cover DMA address/width/repeat behavior, EEPROM serial DMA,
timer cascade/reload, sound FIFO routing/refill, IO lanes, PPU register routing,
BIOS decompression and IRQ return, frame slicing, deterministic snapshots,
reset, demo input, invalid data and local diagnostics severity/deduplication.

## Reporting a failure

Include the game title/code, build version, whether the demo works, renderer
backend, reproduction steps, the status/Output error and relevant Diagnostics
entries. Include emulated PC or SWI number when shown. Avoid uploading private
ROM data in a bug report.
