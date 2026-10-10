--!strict
--[[ Diagnostics (init)

 The always-on catcher. Compose the pieces and expose a tiny API:

   local Diag = require(...Diagnostics)
   Diag.install()                     -- once, at boot
   Diag.capture({ message = ..., kind = ... })
   Diag.registerInvariant("bus.bounds", fn)
   Diag.summary()                     -- { error = n, bug = n, ... }
   Diag.findings({ category = "unfinished" })
   Diag.advice(finding)               -- suggested fix text

 Background behaviour: install() starts a task loop that (a) static-scans the
 emulator's own scripts and (b) runs every registered invariant. Findings stay
 in memory on this client for the current session. It also records the last
 scan time so the dashboard can show when it ran.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Signal = require(ReplicatedStorage.Shared.Signal)

local Classifier = require(script.Classifier)
local Store = require(script.Store)
local StaticScan = require(script.StaticScan)
local Watchdog = require(script.Watchdog)
local Hooks = require(script.Hooks)
local BuildReport = require(ReplicatedStorage.Shared.BuildReport)

export type Finding = Classifier.Finding

type Invariant = { name: string, fn: () -> (boolean, string?) }

local Diag = {}
Diag.VERSION = Config.VERSION

Diag.onFinding = Signal.new()
Diag._store = Store.new(Config.DIAG.maxEvents)
Diag._invariants = {} :: { Invariant }
Diag._installed = false
Diag._lastScan = 0
Diag._scanRuns = 0
Diag._backgroundTask = nil :: thread?
Diag._sourceScanned = false

-- Core capture --------------------------------------------------------------

--- Ingest any raw signal and store a classified finding.
function Diag.capture(signal: {
	message: string,
	source: string?,
	kind: string?,
	stack: string?,
	hint: string?,
	meta: { [string]: any }?,
}): Finding
	if not Config.DIAG.enabled then
		return nil :: any
	end
	local finding = Classifier.makeFinding(signal)
	local stored = Diag._store:add(finding)
	Diag.onFinding:fire(stored)
	-- The originating error is already logged. Logging findings back into the
	-- observed Logger/LogService creates recursive findings.

	return stored
end

--- Convenience wrappers used across the emulator.
function Diag.report(message: string, meta: { [string]: any }?)
	Diag.capture({
		message = message,
		stack = meta and meta.stack,
		source = (meta and meta.source) or "manual",
		kind = (meta and meta.kind) or nil,
		hint = (meta and meta.severity) or nil,
		meta = meta,
	})
end

--- Wrap a hot-path function so any error is recorded and swallowed safely.
function Diag.guard(name: string, fn: (...any) -> ...any)
	return Hooks.guard(name, fn, function(sig) Diag.capture(sig) end)
end

--- Register a runtime invariant checked by the background loop.
function Diag.registerInvariant(name: string, fn: () -> (boolean, string?))
	table.insert(Diag._invariants, { name = name, fn = fn })
end

-- Queries -------------------------------------------------------------------

function Diag.findings(filter: { category: string?, minSeverity: string? }?)
	filter = filter or {}
	local out = {}
	for _, f in Diag._store:all() do
		if filter.category and f.category ~= filter.category then continue end
		out[#out + 1] = f
	end
	return out
end

function Diag.summary()
	return {
		counts = Diag._store:countByCategory(),
		total = Diag._store:count(),
		lastScan = Diag._lastScan,
		scanRuns = Diag._scanRuns,
		stalls = 0,
		sourceHash = BuildReport.sourceHash,
	}
end

--- Human-readable fix suggestion for a finding ("then you can fix it").
function Diag.advice(finding: Finding): string
	local a = {
		error = "Wrap the failing path in Diag.guard and fix the root cause in the referenced module.",
		bug = "Inspect the reported module; likely an off-by-one / bounds / wrap issue. Add an invariant.",
		vulnerability = "Never trust client input: validate on the server, drop loadstring/getfenv, scope remotes.",
		unfinished = "Finish the stub or clearly mark the feature disabled until implemented.",
	}
	local base = a[finding.category] or "Review the referenced source."
	if finding.meta and finding.meta.snippet then
		base = base .. ` Offending line: {finding.meta.snippet}`
	end
	return base
end

-- Background behaviour ------------------------------------------------------

local function runScan()
	Diag._lastScan = os.clock()
	Diag._scanRuns += 1

	-- Source is immutable/protected in ordinary clients. Probe only once.
	if not Diag._sourceScanned then
		Diag._sourceScanned = true
		local ok, hits = false, nil
		if script then
			ok, hits = pcall(StaticScan.scanInstance, script.Parent, {maxLines = 2000})
		end
		if ok and hits then
			for _, f in StaticScan.toFindings(hits) do Diag.onFinding:fire(Diag._store:add(f)) end
		end
	end

	-- (b) invariants
	for _, inv in Diag._invariants do
		local okI, holds, detail = pcall(inv.fn)
		if not okI then
			Diag.capture({ message = `invariant '{inv.name}' errored: {holds}`, source = "invariant", kind = "runtime-error", hint = "error" })
		elseif not holds then
			Diag.capture({ message = `invariant '{inv.name}' violated: {detail or "no detail"}`, source = "invariant", kind = "bug", hint = "warn" })
		end
	end
end

--- Start the background monitor. Returns immediately.
function Diag.install()
	if Diag._installed then return end
	Diag._installed = true
	for _, entry in BuildReport.findings do
		local finding = Classifier.makeFinding({message=entry.message,
			source=entry.source .. ":" .. entry.line, hint=entry.severity, kind=entry.category})
		finding.category = entry.category
		finding.symbol = Classifier.symbolFor(entry.category, entry.message, finding.source)
		Diag._store:add(finding)
	end

	Logger.attachSink(function(level, msg)
		if level == "error" or level == "fatal" or level == "warn" then
			Diag.capture({ message = msg, source = "Logger", kind = level })
		end
	end)

	Hooks.install(function(sig) Diag.capture(sig) end)

	Diag._backgroundTask = task.spawn(function()
		local interval = Config.DIAG.scanInterval
		while Diag._installed do
			task.wait(interval)
			pcall(runScan)
		end
	end)
	Logger.info("DIAG background catcher online (static scan + invariants)")
end

function Diag.setWatchdogReporter(wd: any)
	if wd and wd.setReporter then
		wd:setReporter(function(msg, meta) Diag.report(msg, meta) end)
	end
end

function Diag.shutdown()
	Diag._installed = false
	if Diag._backgroundTask then task.cancel(Diag._backgroundTask); Diag._backgroundTask = nil end
	Hooks.uninstall()
	Diag.onFinding:clear()
end

-- Expose pure modules for tests
Diag._classifier = Classifier
Diag._storeFactory = Store
Diag._staticScan = StaticScan
Diag._watchdogFactory = Watchdog

return Diag
