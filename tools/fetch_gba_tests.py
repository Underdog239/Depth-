#!/usr/bin/env python3
"""Fetch the MIT-licensed jsmolka/gba-tests suite and emit each ROM as a Luau
module of base64 chunks under build/roms/, so the headless harness can load them
(standalone Luau has no filesystem access).

Attribution: the upstream project is MIT licensed and is credited in CREDITS.md,
reproduced into build/roms/NOTICE.txt, and stamped into the header of every
generated module. This repository does not vendor or redistribute the ROMs -
they are downloaded on demand into git-ignored directories.

Results are written by the ROMs into IWRAM at 0x03000000 (hundreds),
0x03000004 (tens), 0x03000008 (ones); all zero means every test passed.
"""

import base64
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, ".tools", "gba-tests")
OUT = os.path.join(ROOT, "build", "roms")

UPSTREAM = "https://github.com/jsmolka/gba-tests"
UPSTREAM_AUTHOR = "Julian Smolka"
UPSTREAM_LICENSE = "MIT"
PINNED_COMMIT = "a7113b67e63f83a9b321696ddd7042ccfad6c881"

CREDIT = (
    "--!nocheck\n"
    "-- Test ROM: {rel}.gba\n"
    "-- Source:  {up}\n"
    "-- Author:  (c) 2019 {author} - {lic} License\n"
    "-- Commit:  {sha}\n"
    "-- Generated locally by tools/fetch_gba_tests.py. LuauGBA does not\n"
    "-- redistribute upstream ROMs; see CREDITS.md and build/roms/NOTICE.txt.\n"
)


def ensure_clone():
    if os.path.isdir(os.path.join(SRC, ".git")):
        return
    os.makedirs(os.path.dirname(SRC), exist_ok=True)
    subprocess.check_call(
        ["gh", "repo", "clone", "jsmolka/gba-tests", SRC, "--", "--depth", "1"]
    )


def write_notice():
    """Reproduce the upstream licence text beside the generated ROMs."""
    lic_path = os.path.join(SRC, "LICENSE")
    if os.path.isfile(lic_path):
        with open(lic_path) as f:
            lic_text = f.read()
    else:
        lic_text = UPSTREAM_LICENSE + " License - see " + UPSTREAM + "/blob/master/LICENSE"

    lines = [
        "Third-party test ROMs used by LuauGBA",
        "=====================================",
        "",
        "Source:  " + UPSTREAM,
        "Author:  " + UPSTREAM_AUTHOR + " (Copyright (c) 2019)",
        "Licence: " + UPSTREAM_LICENSE,
        "Commit:  " + PINNED_COMMIT,
        "",
        "These ROMs are fetched at test time and are NOT redistributed by the",
        "LuauGBA repository. Regenerate them with:",
        "    python3 tools/fetch_gba_tests.py",
        "",
        "Upstream licence text follows.",
        "",
        "-------------------------------------",
        lic_text,
    ]
    with open(os.path.join(OUT, "NOTICE.txt"), "w") as f:
        f.write("\n".join(lines))


def main():
    ensure_clone()
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for dirpath, _, files in os.walk(SRC):
        for name in files:
            if not name.endswith(".gba"):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC)[:-4].replace(os.sep, "_")
            with open(full, "rb") as f:
                data = f.read()
            b64 = base64.b64encode(data).decode()
            chunks = [b64[i:i + 50000] for i in range(0, len(b64), 50000)]
            body = "".join('  "' + c + '",\n' for c in chunks)
            with open(os.path.join(OUT, rel + ".luau"), "w") as f:
                f.write(CREDIT.format(
                    rel=rel.replace("_", "/"),
                    up=UPSTREAM,
                    author=UPSTREAM_AUTHOR,
                    lic=UPSTREAM_LICENSE,
                    sha=PINNED_COMMIT,
                ))
                f.write("return {\n" + body + "}\n")
            count += 1

    write_notice()
    print("emitted " + str(count) + " test ROMs into build/roms/")
    print("  credited to " + UPSTREAM_AUTHOR + " (" + UPSTREAM_LICENSE + ") - " + UPSTREAM)
    print("  attribution written to build/roms/NOTICE.txt and each module header")


if __name__ == "__main__":
    main()
