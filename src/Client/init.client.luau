--!strict
--[[ Client bootstrap (v1.0)

 Brings the whole build up on join, with nothing to run by hand:

   1. background diagnostics catcher
   2. emulator + audio bridge + renderer + input + UI
   3. embedded-ROM auto-load (web/rom-tool.html produces the module)
   4. cross-session persistence via DiagBridge
   5. frame loop with profiling, adaptive pacing and a VU meter
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)
local DiagBridge = require(ReplicatedStorage.Shared.DiagBridge)

local Diagnostics = require(script.Parent.Diagnostics)
local GBA = require(script.Parent.Emulator.GBA)
local ROMLoader = require(script.Parent.Emulator.ROMLoader)
local SaveState = require(script.Parent.Emulator.Save.SaveState)
local Renderer = require(script.Parent.Render)
local InputManager = require(script.Parent.Input)
local UI = require(script.Parent.UI)
local Dashboard = require(script.Parent.UI.DiagDashboard)
local AudioBridge = require(script.Parent.Audio)
local Profiler = require(script.Parent.Optimize.Profiler)
local Adaptive = require(script.Parent.Optimize.Adaptive)
local Watchdog = require(script.Parent.Diagnostics.Watchdog)

-- 1. Background diagnostics ---------------------------------------------------
Diagnostics.install()
local watchdog = Watchdog.new()
Diagnostics.setWatchdogReporter(watchdog)

-- 2. Machine + supporting layers ---------------------------------------------
local profiler = Profiler.new()
local adaptive = Adaptive.new()
local gba = GBA.new({ diag = Diagnostics })
local audio = AudioBridge.new(gba.apu)
local running = false
local paused = false
local frameIndex = 0
local savedState = nil
local lastSync = os.clock()

local ui, renderer, input, dashboard

local function describeRom(info: any, byteCount: number): string
	return string.format("ROM: %s  (%s, %d KiB, save=%s)", info.title, info.gameCode, byteCount // 1024, info.saveType)
end

local function loadRomBytes(bytes: { number })
	local ok, info = pcall(function() return gba:loadROM(bytes) end)
	if not ok then
		Diagnostics.report(`ROM load failed: {info}`, { source = "bootstrap.loadRom", kind = "runtime-error", severity = "error" })
		return false
	end
	running = true
	paused = false
	ui:setStatus(describeRom(info, #bytes))
	if not info.headerChecksumOk then
		Diagnostics.report(`ROM header checksum mismatch for '{info.title}'`, { source = "GBA.loadROM", kind = "bug", severity = "warn" })
	end
	return true
end

local hooks = {
	onLoadROM = function(bytes: { number })
		loadRomBytes(bytes)
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

-- 3. Embedded ROM auto-load ---------------------------------------------------
task.spawn(function()
	local bytes, source = ROMLoader.find()
	if bytes then
		Logger.info(`embedded ROM found via {source} ({#bytes // 1024} KiB)`)
		loadRomBytes(bytes)
	else
		ui:setStatus(`{Config.VERSION} ready - no embedded ROM ({source}). Paste base64 or add Assets.ROM`)
	end
end)

-- 4. Cross-session persistence -----------------------------------------------
task.spawn(function()
	local persisted = DiagBridge.fetch()
	if #persisted > 0 then
		Diagnostics.mergeFindings(persisted)
		Logger.info(`restored {#persisted} findings from the server store`)
	end
end)

-- 5. Invariants the catcher checks in the background --------------------------
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
Diagnostics.registerInvariant("save.size.valid", function()
	local backend = gba.cart and gba.cart.backend
	if not backend then return true end
	return backend.size > 0 and #backend.data == backend.size, "save backend size mismatch"
end)

-- 6. Frame loop ---------------------------------------------------------------
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

		audio:pump()

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

	-- periodic server sync of locally caught findings
	local now = os.clock()
	if now - lastSync > Config.DIAG.syncInterval then
		lastSync = now
		task.spawn(function()
			DiagBridge.push(Diagnostics._store:toArray())
		end)
	end

	if frameIndex % 30 == 0 and running then
		local p = profiler:report()
		local a = audio:stats()
		ui:setStatus(string.format("fps~%.0f  emu %.1fms  present %.1fms  scale %d  %s  audio %.0f%%",
			watchdog:fps(), p.emulate or 0, p.present or 0, adaptive.currentScale, adaptive.mode, a.level * 100))
	end
end

RunService.RenderStepped:Connect(function()
	local ok, err = pcall(onFrame)
	if not ok then
		Diagnostics.report(`frame loop crashed: {err}`, { source = "RenderStepped", kind = "runtime-error", severity = "fatal" })
	end
end)

Logger.info(`LuauGBA {Config.VERSION} online - diagnostics catcher running in the background`)
