# Health checks, recovery and GitHub reports

## In the game

Open **Menu → Health report & background scans**. It shows four categories:
errors, bugs, security findings and unfinished work. Runtime exceptions and
invariants feed a bounded local store. Checks run every 10 seconds. Repository
source findings are generated at build time by `tools/scan_health.py` and include
the exact source fingerprint in `Shared.BuildReport`.

Automatic recovery covers reducing CPU work on sustained slow frames, clearing
held inputs on focus loss/controller disconnect, pausing while the menu is
open, and stopping emulation after an exception. The report gives source
locations and advice. It does not rewrite code or guarantee discovery of all
bugs/vulnerabilities. There is no live GitHub HTTP request from the client.

## On GitHub

`.github/workflows/health.yml` runs on pushes, pull requests and manual dispatch.
A daily schedule is included; GitHub only activates schedules/manual workflow
listing when the workflow exists on the repository's default branch. This task
can push only its assigned branch, so default-branch activation may remain pending.

The workflow scans source, compiles Luau, runs core/regression/device and
conformance tests, checks the client-only place, and verifies that the shipped
installer matches a fresh build. Each run uploads **depth-health** and writes
source findings to the job summary. Failed test steps include their exact error
in the Actions log. It uses read-only repository permissions and does not open
issues, modify your code or execute arbitrary generated patches.

The three declared capability gaps (full PCM audio, partial BIOS and real Studio
acceptance) are shown even when automated checks pass. Token-based source scans
are heuristics, not a full security audit. Review a reported location before
changing it.

## Delivering a patch

Make and test the source fix, regenerate the report, place and installer, then
publish the updated branch. Use the installer in Studio's Command Bar while
stopped. It refuses to overwrite existing objects: back up custom ROM/config,
remove the previous Depth objects, then reinstall. Save the place afterward.
A protected Roblox LocalScript cannot download and replace its own source.

```bash
python3 tools/scan_health.py --output health --module src/Shared/BuildReport.luau
rojo build default.project.json -o Depth-testing.rbxlx
python3 tools/build_installer.py Depth-testing.rbxlx installer/Depth-install.luau
```
