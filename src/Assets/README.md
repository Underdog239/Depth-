# Assets

Placeholder for ROM data baked into the place.

`web/rom-tool.html` generates a `ROM.luau` module; save it here as
`src/Assets/ROM.luau`. Rojo maps this folder to `ReplicatedStorage.Assets`, and
the client auto-loads it on join (see `Emulator/ROMLoader.luau`).

`ROM.luau` is git-ignored on purpose - it contains game data and must not be
committed or published.
