# Audio in the testing build

## What works and what is blocked

The emulator models sound registers, PSG channels and direct-sound FIFOs and
produces signed samples. Roblox's public client APIs play audio assets; they
do not expose a writer for streaming those generated PCM samples to speakers.
Full GBA sound, including direct-sound music, is therefore **not implemented**.
No server, external audio service, exploit APIs or fabricated PCM APIs are used.

The optional adapter approximates **square channels 1 and 2** using an uploaded
256 Hz square-wave loop. Frequency, envelope level, routing, pause and mute are
applied to two local Sound instances at up to 20 updates/second. It does not
reproduce varying duty cycles, wave channel, noise, PCM FIFOs or precise timing.
The UI labels these limitations; a running sample meter is not proof of audible
playback. Without a permitted audio asset, this build remains silent.

## Enable the optional adapter

1. Generate the original loop: `python3 tools/make_audio_asset.py Depth-square-256Hz.wav`.
   The testing download includes this file already.
2. Upload the WAV as audio through Roblox's Creator Dashboard using your own
   creator account. Wait for moderation and grant the experience permission
   to use it. This step requires your Roblox account; the repository cannot
   supply that permission.
3. Play the place, open **Menu → Performance & audio**, enter the numeric asset
   ID, then **Set audio asset → Test tone**. A short 256 Hz tone should play.
4. To keep the ID for future sessions, set `Config.AUDIO.squareAssetId` in
   `ReplicatedStorage.Shared.Config` while Studio is stopped (or edit
   `src/Shared/Config.luau` and rebuild).
5. A ROM using square channels can now produce approximate sound. The built-in
   colour demo does not program sound hardware; use Test tone to check output.

If silent, check Mute, device volume, asset moderation, experience permissions,
and Studio Output. The UI shows a loading/inaccessible status until the asset
loads. Test tone stops after one second. Losing application focus stops sound.

The included loop is original, mono PCM16 at 32768 Hz. It contains no game
music. The adapter's simulated tests verify control logic; real asset playback
and permissions still require Studio/device acceptance.
