--!strict
--[[ Client bootstrap

 Wires the whole thing together on the Roblox client:

   1. start the background diagnostics catcher (runs by itself, forever)
   2. build the emulator, renderer, input manager and UI
   3. run the frame loop with profiling + adaptive pacing
   4. register runtime invariants the catcher checks in the background

 Nothing here needs to be run manually by the user: the catcher and the loop
 start on join, and findings accumulate in the dashboard.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)

local Diagnostics = require(script.Parent.Diagnostics)
local GBA = require(script.Parent.Emulator.GBA)
local SaveState = require(script.Parent.Emulator.Save.SaveState)
local Renderer = require(script.Parent.Render)
local InputManager = require(script.Parent.Input)
local UI = require(script.Parent.UI)
local Dashboard = require(script.Parent.UI.DiagDashboard)
local Profiler = require(script.Parent.Optimize.Profiler)
local Adaptive = require(script.Parent.Optimize.Adaptive)
local Watchdog = require(script.Parent.Diagnostics.Watchdog)

-- 1. Background diagnostics (the catcher) -----------------------------------
Diagnostics.install()
local watchdog = Watchdog.new()
Diagnostics.setWatchdogReporter(watchdog)

-- 2. Build the machine -------------------------------------------------------
local profiler = Profiler.new()
local adaptive = Adaptive.new()
local gba = GBA.new({ diag = Diagnostics })
local running = false
local paused = false
local frameIndex = 0
local savedState = nil

-- 3. UI + renderer + input ---------------------------------------------------
local ui
local renderer
local input
local dashboard

local hooks = {
	onLoadROM = function(bytes: { number })
		local ok, info = pcall(function() return gba:loadROM(bytes) end)
		if not ok then
			Diagnostics.report(`ROM load failed: {info}`, { source = "hooks.onLoadROM", kind = "runtime-error", severity = "error" })
			return
		end
		running = true
		paused = false
		ui:setStatus(string.format("ROM: %s  (%s, %d KiB, save=%s)", info.title, info.gameCode, #bytes // 1024, info.saveType))
		if not info.headerChecksumOk then
			Diagnostics.report(`ROM header checksum mismatch for '{info.title}'`, { source = "GBA.loadROM", kind = "bug", severity = "warn" })
		end
	end,
	onPlayPause = function()
		paused = not paused
		return not paused
	end,
	onReset = function()
		gba:reset()
		ui:setStatus("reset")
	end,
	onScale = function(scale: number)
		renderer:setScale(scale)
	end,
	onSaveState = function()
		savedState = SaveState.save(gba)
		ui:setStatus("state saved (in memory)")
	end,
	onLoadState = function()
		if savedState and SaveState.load(gba, savedState) then
			ui:setStatus("state restored")
		else
			ui:setStatus("no saved state yet")
		end
	end,
	onToggleDiag = function()
		dashboard:toggle()
	end,
}

ui = UI.new(hooks)
renderer = Renderer.new(ui.screenHost, { scale = Config.RENDER.scale })
input = InputManager.new()
dashboard = Dashboard.new(Diagnostics, ui.gui)

-- 4. Runtime invariants checked by the background catcher --------------------
Diagnostics.registerInvariant("cpu.pc.inrange", function()
	local pc = gba.cpu.regs[16]
	return pc >= 0 and pc < 0x10000000, `PC out of range: 0x{string.format("%08X", pc)}`
end)
Diagnostics.registerInvariant("cpu.mode.valid", function()
	local m = gba.cpu.mode
	local ok = m == 0x10 or m == 0x11 or m == 0x12 or m == 0x13 or m == 0x17 or m == 0x1B or m == 0x1F
	return ok, `invalid CPSR mode 0x{string.format("%02X", m)}`
end)
Diagnostics.registerInvariant("ppu.line.inrange", function()
	local line = gba.ppu.line
	return line >= 0 and line <= 227, `PPU line out of range: {line}`
end)
Diagnostics.registerInvariant("bus.no.nan", function()
	return gba.cpu.regs[16] == gba.cpu.regs[16], "PC became NaN"
end)

-- 5. Frame loop --------------------------------------------------------------
local function onFrame()
	local frameStart = os.clock()
	frameIndex += 1

	input:pollStick()
	if running and not paused then
		gba:setKeys(input.mask)
		watchdog:beginFrame(frameIndex)
		profiler:beginSection("emulate")
		local ok, err = pcall(function() gba:runFrame() end)
		profiler:endSection("emulate")
		watchdog:endFrame(frameIndex, gba.bus.cycles)
		if not ok then
			Diagnostics.report(`emulation error: {err}`, { source = "frameLoop", kind = "runtime-error", severity = "error", stack = debug.traceback() })
			running = false
		end
		if adaptive:shouldPresent(frameIndex) then
			profiler:beginSection("present")
			local okP, errP = pcall(function() renderer:present(gba:framebuffer()) end)
			profiler:endSection("present")
			if not okP then
				Diagnostics.report(`present error: {errP}`, { source = "renderer", kind = "runtime-error", severity = "error" })
			end
		end
	end

	local frameMs = (os.clock() - frameStart) * 1000
	adaptive:sample(frameMs)
	if frameIndex % 30 == 0 and running then
		local p = profiler:report()
		ui:setStatus(string.format("fps~%.0f  emulate %.1fms  present %.1fms  scale %d  mode %s",
			watchdog:fps(), p.emulate or 0, p.present or 0, adaptive.currentScale, adaptive.mode))
	end
end

RunService.RenderStepped:Connect(function()
	local ok, err = pcall(onFrame)
	if not ok then
		Diagnostics.report(`frame loop crashed: {err}`, { source = "RenderStepped", kind = "runtime-error", severity = "fatal" })
	end
end)

Logger.info(`LuauGBA {Config.VERSION} client online - diagnostics catcher running in the background`)
