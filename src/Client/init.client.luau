--!strict
--[[ Client bootstrap (v1.0)

 Brings the whole build up on join, with nothing to run by hand:

   1. background diagnostics catcher
   2. emulator + audio bridge + renderer + input + UI
   3. embedded-ROM auto-load (web/rom-tool.html produces the module)
   4. frame loop with profiling, adaptive pacing and a VU meter
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)

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
local UIS = game:GetService("UserInputService")
local adaptive = Adaptive.new(UIS.TouchEnabled)
local menuOpen, focused = true, true
local gba = GBA.new({ diag = Diagnostics })
local audio = AudioBridge.new(gba.apu)
local running = false
local paused = false
local frameIndex = 0
local savedState = nil
local emulationDebt = 0

local ui, renderer, input, dashboard

local function describeRom(info: any, byteCount: number): string
	return string.format("ROM: %s  (%s, %d KiB, save=%s)", info.title, info.gameCode, byteCount // 1024, info.saveType)
end

local function loadRomBytes(bytes: buffer)
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
	onTouch = function(source, bit, down) if input then input:touch(source, bit, down) end end,
	onMenuChange = function(open)
		menuOpen = open
		if input then input:setEnabled(not open and focused); input.capture = nil end
		audio:setActive(running and not paused and not open and focused)
	end,
	onRemap = function(bit, done)
		game:GetService("GuiService").SelectedObject = nil
		input:beginMapping(bit, done)
	end,
	onResetBindings = function() input:resetBindings() end,
	describeBinding = function(bit) return input:describe(bit) end,
	onLowPower = function(enabled) adaptive:setLowPower(enabled) end,
	onMute = function(muted) audio:setMuted(muted) end,
	onAudioAsset = function(text) return audio:setAsset(text) end,
	onTestTone = function() return audio:testTone() end,
	onDemo = function() loadRomBytes(DemoROM.create()) end,
	onLoadROM = function(bytes: buffer)
		return loadRomBytes(bytes)
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
			renderer:present(gba:framebuffer(), true)
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
input:setEnabled(false)
input.onMenu = function() ui:showMenu(not ui.open) end
ui:updateBindings()
UIS.WindowFocusReleased:Connect(function()
	focused = false; input:setEnabled(false); audio:setActive(false); audio:stopTest()
end)
UIS.WindowFocused:Connect(function()
	focused = true; input:setEnabled(not menuOpen)
end)
dashboard = Dashboard.new(Diagnostics, ui.gui.Parent)

-- 3. Embedded ROM auto-load ---------------------------------------------------
task.spawn(function()
	local ok, bytes, source = pcall(ROMLoader.find)
	if not ok then ui:setStatus("Embedded ROM failed: " .. tostring(bytes)); return end
	if bytes then
		Logger.info(`embedded ROM found via {source} ({buffer.len(bytes) // 1024} KiB)`)
		if loadRomBytes(bytes) then ui:showMenu(false) end
	else
		ui:setStatus(`{Config.VERSION} ready - no embedded ROM ({source}). Paste base64 or add Assets.ROM`)
	end
end)

-- 4. Invariants the catcher checks in the background --------------------------
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

-- 5. Frame loop ---------------------------------------------------------------
local function onFrame(dt: number)
	local frameStart = os.clock()
	frameIndex += 1

	local playing = running and not paused and not menuOpen and focused
	audio:setActive(playing)
	if playing then
		emulationDebt = math.min(emulationDebt + dt, 2 / Config.FPS)
	end
	if playing and emulationDebt >= 1 / Config.FPS then
		gba:setKeys(input.mask)
		watchdog:beginFrame(frameIndex)
		profiler:beginSection("emulate")
		local ok, err = pcall(function() gba:runFrame(adaptive.sliceMs) end)
		profiler:endSection("emulate")
		watchdog:endFrame(frameIndex, gba.bus.cycles)
		if not ok then
			Diagnostics.report(`emulation error: {err}`, { source = "frameLoop", kind = "runtime-error", severity = "error", stack = debug.traceback() })
			running = false
			audio:setActive(false)
			ui:setRunning(false)
			ui:setStatus("Emulation stopped: " .. tostring(err))
		end


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
	if playing then adaptive:sample(frameMs) end
	audio:pump()
	if frameIndex % 60 == 0 then ui:setAudioStatus(audio:status()) end

	if frameIndex % 30 == 0 then
		local p = profiler:report()
		-- UI refresh is throttled independently of emulation.
		ui:setMetrics(string.format("%s | work %.1fms | budget %.0fms | %.0f FPS",
			renderer.backend, p.emulate or 0, adaptive.sliceMs, 1000 / adaptive.averageMs))
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(onFrame, dt)
	if not ok then
		running = false
		audio:setActive(false)
		ui:setRunning(false)
		ui:setStatus("Frame error: " .. tostring(err))
		Diagnostics.report(`frame loop crashed: {err}`, { source = "RenderStepped", kind = "runtime-error", severity = "fatal" })
	end
end)

Logger.info(`LuauGBA {Config.VERSION} online - diagnostics catcher running in the background`)
