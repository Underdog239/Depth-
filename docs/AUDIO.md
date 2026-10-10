# Audio

## What is implemented

The APU is a full register-level model:

| block | state |
|---|---|
| Channel 1 | duty, envelope, sweep, length, frequency |
| Channel 2 | duty, envelope, length, frequency |
| Channel 3 | 32-step wave RAM, volume shift, length, frequency |
| Channel 4 | noise LFSR (15- and 7-bit), divisor, prescaler, envelope |
| FIFO A / B | DMA sound byte queues |
| Mixer | SOUNDCNT_L volume + channel enable, SOUNDCNT_H FIFO mixing, SOUNDBIAS |

Channels are clocked from the master cycle counter, envelopes/lengths are folded
into the sample loop, and the mixer emits signed 8-bit samples at
`Config.AUDIO.sampleRate` into a ring buffer.

Because the registers behave correctly, titles that poll sound state (or that
use audio to drive game logic) work. `Tests/run.luau` covers register round
trips, channel triggering, sample production and FIFO draining.

## The Roblox wall

**Roblox exposes no PCM playback API.** There is no way to hand a buffer of
samples to the engine and have it play them. That is a platform limitation, not
something the emulator can work around by trying harder.

So this build does the two things that *are* possible:

1. **Monitor** (default). Samples are produced, and `Audio/init.luau` turns them
   into a smoothed level + peak. The status line shows a live percentage, which
   is direct evidence the audio path is running.
2. **Synth** (`Config.AUDIO.mode = "synth"`). If a project supplies per-channel
   `Sound` assets, the bridge drives them. Without supplied assets there is
   nothing to play, so it stays on the monitor path.

## Making it audible

If you want actual sound, the practical routes are:

* supply four looping square-wave `Sound` assets and map them to channel
  frequency/volume in `Audio/init.luau`; or
* route `Apu:readSamples()` to any future Roblox audio API, or out of the
  experience entirely (for example a companion process); or
* accept the monitor path and treat audio as modelled-but-silent.

`Apu:setSink(fn)` is the single extension point - everything else is already
wired.

## Tuning

```lua
Config.AUDIO = {
    enabled = true,
    sampleRate = 32768,   -- lower = cheaper, coarser
    mode = "monitor",     -- "off" | "monitor" | "synth"
    master = 0.6,
}
```

Set `mode = "off"` if you want the registers modelled with no mixing cost at
all.
