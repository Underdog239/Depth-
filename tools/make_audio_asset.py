#!/usr/bin/env python3
"""Generate an original 256 Hz, 50% duty square loop for Roblox asset upload."""
import argparse
import math
import struct
import wave
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output')
args = parser.parse_args()
with wave.open(args.output, 'wb') as audio:
    audio.setparams((1, 2, 32768, 0, 'NONE', 'not compressed'))
    audio.writeframes(b''.join(struct.pack('<h', 8192 if i % 128 < 64 else -8192) for i in range(32768)))
print('Generated original mono 256 Hz square wave, one second, 32768 Hz PCM16')
