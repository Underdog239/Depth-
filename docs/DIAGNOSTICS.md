# Diagnostics - the background catcher

## Goal

Answer these questions **without the user running anything**:

* Did anything error?
* Is there a bug (wrong behaviour that did not throw)?
* Is there a vulnerability?
* Is there unfinished code?
* Where exactly, and how do I fix it?

## Pipeline

```
signal  ->  Classifier  ->  Store  ->  Dashboard
  ^            |              |
  |            |              +--> Persistence (DataStore)
  |            +--> advice()
sources:
  ScriptContext.Error, LogService.MessageOut, Logger sink,
  Diag.guard(), invariants, watchdog stalls, StaticScan
```

## Categories

| category | trigger examples |
|---|---|
| `error` | uncaught runtime error, guarded call failure |
| `bug` | out-of-range PC/PPU line, NaN, stall, wrap/overflow signals |
| `vulnerability` | `loadstring`, `getfenv`, unvalidated remotes, client DataStore |
| `unfinished` | `TODO`/`FIXME`/`XXX`, stub markers, unimplemented opcodes |

Classification is deterministic and unit-tested (`Tests/run.luau`).

## De-duplication

The dedup symbol is `category|source|normalised-message`, where numbers and hex
literals are replaced by `N`. So `read8(0x1FF)` and `read8(0x200)` collapse into
one finding with `count = 2` instead of flooding the list.

## Persistence and "without running the script"

* The client keeps a session store and mirrors findings through the logger sink.
* The server (`src/Server/DiagServer.server.luau`) owns a DataStore and exposes
  two remotes: `GetFindings` and `PushFindings`.
* The dashboard reads the server copy, so findings from **previous sessions**
  are visible immediately on join - nothing has to be re-triggered.

The server half deliberately demonstrates the secure pattern the catcher itself
looks for: strict type/length validation, a per-player rate limit, no
`loadstring`, no trusting client payloads.

## Extending it

```lua
-- runtime invariant, checked on the background scan timer
Diag.registerInvariant("bus.bounds", function()
	return someAddress < 0x10000000, "address escaped the bus"
end)

-- guard a risky call so failures become findings instead of crashes
local safe = Diag.guard("decodeROM", decodeROM)

-- report something explicitly
Diag.report("ROM header checksum mismatch", { kind = "bug", severity = "warn" })
```

## Reading the dashboard

Each row shows the category (colour-coded), the occurrence count, the message,
and a one-line suggested fix generated from the category plus the offending
snippet. The header shows live counts per category and how many background scans
have run - proof the catcher is working even if it found nothing.
