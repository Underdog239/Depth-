#!/usr/bin/env python3
"""Copy src/ into build/ rewriting Roblox requires into Luau require-by-string
so the pure modules can be executed by the standalone `luau` binary.
"""
import os, re, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")

RE_REPL = re.compile(r"require\(ReplicatedStorage\.Shared\.([A-Za-z0-9_]+)\)")
RE_SHARED = re.compile(r'require\(game:GetService\("ReplicatedStorage"\)\.Shared\.([A-Za-z0-9_]+)\)')
RE_SCRIPT = re.compile(r"require\(script((?:\.[A-Za-z0-9_]+)+)\)")

PRELUDE = (
    'local Enum = { KeyCode = setmetatable({}, { __index = function(t, k) '
    'local v = "KeyCode." .. k; rawset(t, k, v); return v end }) }\n'
)


def rel(from_dir, to_path):
    r = os.path.relpath(to_path, from_dir).replace(os.sep, "/")
    if not r.startswith("."):
        r = "./" + r
    return r


def rewrite(text, out_dir):
    def shared(m):
        return 'require("%s")' % rel(out_dir, os.path.join(BUILD, "Shared", m.group(1)))

    def script_req(m):
        segs = m.group(1).split(".")[1:]
        ups = 0
        parts = []
        for seg in segs:
            if seg == "Parent":
                ups += 1
            else:
                parts.append(seg)
        ups = max(0, ups - 1)
        path = "../" * ups + "/".join(parts)
        if not path.startswith("."):
            path = "./" + path
        return 'require("%s")' % path

    text = RE_SHARED.sub(shared, text)
    text = RE_REPL.sub(shared, text)
    text = RE_SCRIPT.sub(script_req, text)
    text = text.replace('game:GetService("ReplicatedStorage")', '({ Shared = {} })')
    return text


def main():
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    for dirpath, _, files in os.walk(SRC):
        for name in files:
            if not name.endswith(".luau"):
                continue
            full = os.path.join(dirpath, name)
            out_dir = os.path.join(BUILD, os.path.relpath(dirpath, SRC))
            os.makedirs(out_dir, exist_ok=True)
            with open(full) as f:
                text = f.read()
            with open(os.path.join(out_dir, name), "w") as f:
                f.write(PRELUDE + rewrite(text, out_dir))
    os.makedirs(os.path.join(BUILD, "Tests"), exist_ok=True)
    for name in os.listdir(os.path.join(ROOT, "Tests")):
        if name.endswith(".luau"):
            shutil.copy(os.path.join(ROOT, "Tests", name), os.path.join(BUILD, "Tests", name))
    print("prepared build/")


if __name__ == "__main__":
    main()
