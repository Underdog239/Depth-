# Avalon R1 — handoff note

**What this is:** the complete source for **Avalon R1**, a high-performance
software 3D renderer for Roblox, written in Luau. It renders real, textured,
depth-tested 3D scenes entirely inside a GUI via `EditableImage` — no parts, no
workspace meshes, no engine lighting.

It is finished and verified. It just needs to be moved to its own repository.

## Where it should go

`Underdog239/Avalon-r1` — that repo exists but currently only holds a placeholder
file called `Read me`.

## Why it is not there yet

The `cline-cloud[bot]` GitHub App installation does **not** include
`Avalon-r1`, so every write path is refused:

```
git push                     -> Permission to Underdog239/Avalon-r1.git denied
DELETE /contents/<file>      -> 403 Resource not accessible by integration
POST   /git/blobs            -> 403 Resource not accessible by integration
```

`gh api /installation/repositories` reports `"repository_selection": "selected"`
with only `Depth-` in the list. It needs to be **All repositories**, or
`Avalon-r1` added explicitly, at
https://github.com/settings/installations -> **cline-cloud** -> **Configure**.

A credential minted before that change will not pick it up — start a **new chat**
after fixing the setting.

## How to finish (for the next agent)

```bash
# 1. get this folder
git clone --depth 1 https://github.com/Underdog239/Depth-.git depth
#    (the folder is AvalonR1/)

# 2. put it in its real home
git clone https://github.com/Underdog239/Avalon-r1 avalon-r1
cd avalon-r1
git rm "Read me"
cp -r ../depth/AvalonR1/. .
git add -A
git commit -m "Add Avalon R1: high-performance software 3D renderer for Roblox"
git push origin main
```

Then optionally delete `HANDOFF.md` (this file) from the new repo.

## Verify it before shipping

```bash
cd AvalonR1
python3 Tests/bundle.py
luau Tests/combined.luau      # must end with: ALL TESTS PASS
```

Every file also compiles cleanly:

```bash
for f in src/Avalon/*.luau src/Demo/*.luau; do luau-compile --binary "$f" >/dev/null || echo "FAIL $f"; done
```

## What is in here

| Path | Contents |
|---|---|
| `src/Avalon/` | The renderer: `Mat4`, `Camera`, `Mesh`, `Texture`, `Framebuffer`, `Rasterizer`, `Renderer`, `init` |
| `src/Demo/` | A demo scene (textured floor, spinning cube, lit sphere, torus) |
| `Tests/` | Headless test suite that runs the real modules outside Roblox |
| `docs/ARCHITECTURE.md` | Full pipeline walkthrough |
| `CREDITS.md` | The Roblox developers whose published work informed the design |
| `README.md` | API reference, performance notes, install instructions |
| `default.project.json` | Rojo project |

## Requirements

Roblox client with `EditableImage` available (`AssetService:CreateEditableImage`).
Nothing else — no packages, no HTTP, no server, no external assets.
