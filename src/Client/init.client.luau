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

local Diagnostics = require(script.Diagnostics)
local GBA = require(script.Emulator.GBA)
local ROMLoader = require(script.Emulator.ROMLoader)
local Base64 = require(ReplicatedStorage.Shared.Base64)
local DemoROM = require(script.Emulator.DemoROM)
local SaveState = require(script.Emulator.Save.SaveState)
local Renderer = require(script.Render)
local InputManager = require(script.Input)
local UI = require(script.UI)
local Dashboard = require(script.UI.DiagDashboard)
local AudioBridge = require(script.Audio)
local Profiler = require(script.Optimize.Profiler)
local Adaptive = require(script.Optimize.Adaptive)
local Watchdog = require(script.Diagnostics.Watchdog)

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
local emulationDebt = 0

local ui, renderer, input, dashboard

local function describeRom(info: any, byteCount: number): string
	return string.format("ROM: %s  (%s, %d KiB, save=%s)", info.title, info.gameCode, byteCount // 1024, info.saveType)
end

local function loadRomBytes(bytes: { number })
	local ok, info = pcall(function() return gba:loadROM(bytes) end)
	if not ok then
		ui:setStatus("ROM load failed: " .. tostring(info))
		Diagnostics.report(`ROM load failed: {info}`, { source = "bootstrap.loadRom", kind = "runtime-error", severity = "error" })
		return false
	end
	running = true
	paused = false
	emulationDebt = 0
	savedState = nil
	ui:setRunning(true)
	ui:setStatus(describeRom(info, gba.cart.size))
	if not info.headerChecksumOk then
		Diagnostics.report(`ROM header checksum mismatch for '{info.title}'`, { source = "GBA.loadROM", kind = "bug", severity = "warn" })
	end
	return true
end

local hooks = {
	onDemo = function() loadRomBytes(DemoROM.create()) end,
	onLoadROM = function(bytes: { number })
		loadRomBytes(bytes)
	end,
	onPlayPause = function()
		if not running then return false end
		paused = not paused
		return not paused
	end,
	onReset = function()
		if not gba.cart then return end
		gba:reset()
		running, paused = true, false
		ui:setRunning(true)
		ui:setStatus("Reset complete")
	end,
	onScale = function(scale: number)
		renderer:setScale(scale)
	end,
	onSaveState = function()
		if not gba.cart then ui:setStatus("Load a ROM first"); return end
		savedState = SaveState.save(gba)
		ui:setStatus("state saved (in memory)")
	end,
	onLoadState = function()
		if savedState and SaveState.load(gba, savedState) then
			running = true
			renderer:present(gba:framebuffer())
			ui:setRunning(not paused)
			ui:setStatus("State restored")
		else
			ui:setStatus("no saved state yet")
		end
	end,
	onExportSave = function()
		if not gba.cart then ui:setStatus("Load a ROM first"); return nil end
		ui:setStatus("Copy the save text and keep it in a file to import next session")
		return Base64.encode(gba:saveBytes())
	end,
	onImportSave = function(text)
		if not gba.cart then ui:setStatus("Load a ROM first"); return end
		local ok, bytes = pcall(Base64.decode, text)
		if not ok or #bytes ~= gba.cart.backend.size then ui:setStatus("Save data is invalid or has the wrong size for this game"); return end
		gba:loadSaveBytes(bytes)
		gba:reset()
		savedState = nil
		running, paused = true, false
		ui:setRunning(true)
		ui:setStatus("Battery save imported; game restarted")
	end,
	onToggleDiag = function()
		dashboard:toggle()
	end,
}

ui = UI.new(hooks)
renderer = Renderer.new(ui.screenHost, { scale = Config.RENDER.scale })
input = InputManager.new()
dashboard = Dashboard.new(Diagnostics, ui.gui.Parent)

-- 3. Embedded ROM auto-load ---------------------------------------------------
task.spawn(function()
	local ok, bytes, source = pcall(ROMLoader.find)
	if not ok then ui:setStatus("Embedded ROM failed: " .. tostring(bytes)); return end
	if bytes then
		Logger.info(`embedded ROM found via {source} ({buffer.len(bytes) // 1024} KiB)`)
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
	if not backend or backend.type == "NONE" then return true end
	return backend.size > 0 and #backend.data == backend.size, "save backend size mismatch"
end)

-- 6. Frame loop ---------------------------------------------------------------
local function onFrame(dt: number)
	local frameStart = os.clock()
	frameIndex += 1

	input:pollStick()
	if running and not paused then
		emulationDebt = math.min(emulationDebt + dt, 2 / Config.FPS)
	end
	if running and not paused and emulationDebt >= 1 / Config.FPS then
		gba:setKeys(input.mask)
		watchdog:beginFrame(frameIndex)
		profiler:beginSection("emulate")
		local ok, err = pcall(function() gba:runFrame(Config.CORE.clientSliceMs) end)
		profiler:endSection("emulate")
		watchdog:endFrame(frameIndex, gba.bus.cycles)
		if not ok then
			Diagnostics.report(`emulation error: {err}`, { source = "frameLoop", kind = "runtime-error", severity = "error", stack = debug.traceback() })
			running = false
			ui:setRunning(false)
			ui:setStatus("Emulation stopped: " .. tostring(err))
		end

		audio:pump()

		if gba.ppu.frameComplete then
			emulationDebt = math.max(0, emulationDebt - 1 / Config.FPS)
		end
		if gba.ppu.frameComplete and adaptive:shouldPresent(gba.ppu.frame) then
			profiler:beginSection("present")
			local okP, errP = pcall(function() renderer:present(gba:framebuffer()) end)
			profiler:endSection("present")
			if not okP then
				Diagnostics.report(`present error: {errP}`, { source = "renderer", kind = "runtime-error", severity = "error" })
			end
		end
	end

	local frameMs = math.max(dt, os.clock() - frameStart) * 1000
	if running and not paused then adaptive:sample(frameMs) end
	if renderer.currentScale ~= adaptive.currentScale then
		renderer:setScale(adaptive.currentScale)
		ui:setScale(adaptive.currentScale)
	end

	-- periodic server sync of locally caught findings
	local now = os.clock()
	if now - lastSync > Config.DIAG.syncInterval then
		lastSync = now
		task.spawn(function()
			DiagBridge.push(Diagnostics._store:toArray())
		end)
	end

	if frameIndex % 30 == 0 and running and not paused then
		local p = profiler:report()
		local a = audio:stats()
		ui:setMetrics(string.format("emu %.1fms | present %.1fms | %s | audio monitor %.0f%%",
			p.emulate or 0, p.present or 0, renderer.backend, a.level * 100))
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(onFrame, dt)
	if not ok then
		running = false
		ui:setStatus("Frame error: " .. tostring(err))
		Diagnostics.report(`frame loop crashed: {err}`, { source = "RenderStepped", kind = "runtime-error", severity = "fatal" })
	end
end)

Logger.info(`LuauGBA {Config.VERSION} online - diagnostics catcher running in the background`)
