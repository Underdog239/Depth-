# Tests

A headless harness that runs the **real** Avalon R1 modules outside Roblox and
asserts on the framebuffer they produce. It is how the renderer was developed —
it caught three genuine bugs (a `buffer.fill` argument-order error, an index-hole
bug in every mesh generator, and an inside-out torus winding) that would
otherwise only have shown up in Studio.

## Running

Requires the [standalone Luau CLI](https://github.com/luau-lang/luau/releases)
(`luau`) on your `PATH`, and Python 3.

```bash
python3 Tests/bundle.py
luau Tests/combined.luau
```

Expected output ends with:

```
ALL TESTS PASS
```

## How it works

`stubs.luau` implements the handful of Roblox globals the renderer touches —
`Vector3`, `Vector2`, `Color3`, `Instance`, `UDim2`, `Enum`, `Content`, and a
fake `AssetService` whose `EditableImage` just records uploads. Everything else
(`buffer`, `math`, `os.clock`) is real Luau.

`bundle.py` then inlines each module in dependency order, because the standalone
CLI sandboxes module globals. `suite.luau` is the actual test list.

## What is covered

- **`Mat4`** — perspective `w` equals view distance; view+projection places a
  point at the right depth.
- **Mesh generators** — every generator produces complete indices, aligned
  vertex arrays, and no dangling indices (this is the check that caught the
  hole bug).
- **Rasterization** — a cube renders and covers a plausible screen area.
- **Depth buffer** — a nearer red cube wins over a farther blue one regardless
  of draw order.
- **Back-face culling** — geometry behind the camera draws nothing.
- **Near-plane clipping** — a huge plane straddling the camera is cut, not
  smeared, and does not error.
- **Shading modes** — `gouraud` (sphere) and `textured` (torus) both produce
  visible pixels.
- **Textures** — checker sampling lands on the right texels and wrap repeats.
