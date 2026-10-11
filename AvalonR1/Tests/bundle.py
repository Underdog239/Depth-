#!/usr/bin/env python3
"""Bundle Avalon R1 + the headless stubs into one Luau file so the renderer can
be executed (and asserted on) outside Roblox.

    python3 Tests/bundle.py
    luau Tests/combined.luau

The standalone Luau CLI gives every required module its own globals, so the
modules cannot simply `require` each other in that environment. This script
inlines each module as an IIFE and rewrites `require(script.Parent.X)` to a
lookup in a shared table.
"""

import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "Tests"

# Order matters: a module may only reference modules defined before it.
ORDER = ["Mat4", "Framebuffer", "Camera", "Mesh", "Texture", "Rasterizer", "Renderer"]

REQUIRE_RE = re.compile(r'require\(script\.(?:Parent\.)?([A-Za-z0-9_]+)\)')


def main() -> None:
    parts = [(TESTS / "stubs.luau").read_text(), "\nlocal MODULES = {}\n"]
    for name in ORDER:
        body = (ROOT / "src" / "Avalon" / f"{name}.luau").read_text()
        body = REQUIRE_RE.sub(r"MODULES.\1", body)
        parts.append(f"\nMODULES.{name} = (function()\n{body}\nend)()\n")
    parts.append("\n" + (TESTS / "suite.luau").read_text())

    out = TESTS / "combined.luau"
    out.write_text("\n".join(parts))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
