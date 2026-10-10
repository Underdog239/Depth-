# Audio status

The testing build models sound registers, PSG channels and direct-sound FIFOs.
Timers clock FIFO playback and request DMA1/2 refills. Generated samples can be
read with `Apu:readSamples()` or consumed through `Apu:setSink(fn)`.

**There is no audible playback adapter in this build.** `Audio/init.luau`
computes a level/peak monitor from generated samples. The previous empty synth
adapter has been removed from the advertised configuration.

Set `Config.AUDIO.mode = "off"` to disable sample mixing while retaining timer
and register behavior. `"monitor"` generates samples for the status display.
PSG/sweep/mixer accuracy is experimental and needs audio conformance coverage.
Any future playback implementation must verify the Roblox APIs and asset
requirements available at that time.
