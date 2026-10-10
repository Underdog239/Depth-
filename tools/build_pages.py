#!/usr/bin/env python3
"""Build an allowlisted GitHub Pages site; never publish local ROMs or launchers."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def build(destination):
    destination = Path(destination)
    # Refuse stale/unrelated contents rather than risk uploading private files.
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Site output must be an empty directory')
    destination.mkdir(parents=True, exist_ok=True)
    helper = (ROOT / 'web' / 'rom-tool.html').read_bytes()
    (destination / 'index.html').write_bytes(helper)
    (destination / 'rom-tool.html').write_bytes(helper)
    (destination / '.nojekyll').touch()
    print('Built static ROM helper: index.html, rom-tool.html, .nojekyll')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination')
    build(parser.parse_args().destination)
