--!strict
--[[ Shared/Config.luau -- single source of truth for tunables.
     Everything the "optimizer" and "diagnostics" layers care about lives here
     so behaviour is universal across client (and optional server) contexts. ]]

local Config = {}

-- Emulation clock targets ---------------------------------------------------
-- GBA: 16.777216 MHz CPU, 59.7275 Hz display, 280896 cycles per frame.
Config.CPU_HZ = 16777216
Config.FPS = 59.7275
Config.CYCLES_PER_FRAME = 280896
Config.SCREEN_W = 240
Config.SCREEN_H = 160
Config.FRAME_PIXELS = Config.SCREEN_W * Config.SCREEN_H

-- Renderer ------------------------------------------------------------------
Config.RENDER = {
	-- Integer scale applied to the 240x160 surface.
	scale = 2,
	-- "native" blits every produced frame; "adaptive" drops frames to hold FPS.
	mode = "native" :: "native" | "adaptive" | "tile",
	minFps = 30,
	targetFps = 60,
	autoScale = true,
}

-- Core loop -----------------------------------------------------------------
Config.CORE = {
	-- Hard ceiling on emulated instructions per rendered frame. Prevents a
	-- runaway frame from freezing the Roblox client (watchdog also guards).
	maxCyclesPerFrame = Config.CYCLES_PER_FRAME * 2,
	-- Allow the loop to skip VBlank detection and run a fixed budget instead.
	skipFrameCap = false,
	-- Enable dynamic recompilation-lite block cache (see Optimize/BlockCache).
	useBlockCache = true,
	-- Emit IRQ diagnostics + trace only when true (very costly).
	traceInstructions = false,
}

-- Diagnostics ---------------------------------------------------------------
Config.DIAG = {
	enabled = true,
	-- Background scanner cadence (seconds).
	scanInterval = 2.0,
	-- Persist findings so they survive a rejoin: Roblox DataStore (server) or
	-- an in-memory + LogService mirror (client).
	persist = true,
	dataStoreName = "GBADIAG_v1",
	-- Ring buffer size for captured events.
	maxEvents = 500,
	-- Minimum severity to keep. "info"|"warn"|"error"|"fatal"
	minSeverity = "info",
	-- Categories the catcher tracks by default.
	categories = { "error", "bug", "vulnerability", "unfinished" },
	-- Watchdog: if the emulator loop stalls longer than this, capture a report.
	stallMs = 250,
}

-- Input ---------------------------------------------------------------------
Config.INPUT = {
	-- Gamepad/Keyboard -> GBA key bit. Bits follow REG_KEYINPUT ordering.
	-- 0=A 1=B 2=Select 3=Start 4=Right 5=Left 6=Up 7=Down 8=R 9=L
	defaultKeyboard = {
		[Enum.KeyCode.Z] = 0,
		[Enum.KeyCode.X] = 1,
		[Enum.KeyCode.RightShift] = 2,
		[Enum.KeyCode.Return] = 3,
		[Enum.KeyCode.Right] = 4,
		[Enum.KeyCode.Left] = 5,
		[Enum.KeyCode.Up] = 6,
		[Enum.KeyCode.Down] = 7,
		[Enum.KeyCode.C] = 8,
		[Enum.KeyCode.A] = 9,
	},
	defaultGamepad = {
		[Enum.KeyCode.ButtonA] = 0,
		[Enum.KeyCode.ButtonB] = 1,
		[Enum.KeyCode.ButtonSelect] = 2,
		[Enum.KeyCode.ButtonStart] = 3,
		[Enum.KeyCode.DPadRight] = 4,
		[Enum.KeyCode.DPadLeft] = 5,
		[Enum.KeyCode.DPadUp] = 6,
		[Enum.KeyCode.DPadDown] = 7,
		[Enum.KeyCode.ButtonR1] = 8,
		[Enum.KeyCode.ButtonL1] = 9,
	},
	-- Deadzone for analog sticks mapped to the D-Pad.
	stickDeadzone = 0.25,
}

Config.VERSION = "0.1.0"

return Config
