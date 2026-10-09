--!strict
--[[ Diagnostics/Watchdog.luau

 Guards the emulator loop. If a frame takes longer than `stallMs` we capture a
 finding (the classic "infinite loop / runaway opcode" bug) and hand the caller
 a chance to bail out of the frame, keeping the client responsive.

 Also tracks cumulative FPS so the dashboard can show real performance and the
 optimizer can react (frame-skip / scale-down).
 ]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

export type Watchdog = {
	beginFrame: (self: Watchdog, id: number) -> (),
	endFrame: (self: Watchdog, id: number, cycles: number) -> (),
	fps: (self: Watchdog) -> number,
	avgFrameMs: (self: Watchdog) -> number,
	stalls: (self: Watchdog) -> number,
	setReporter: (self: Watchdog, fn: (msg: string, meta: any?) -> ()) -> (),
}

local Watchdog = {}
Watchdog.__index = Watchdog

function Watchdog.new(): Watchdog
	return setmetatable({
		_frameStart = 0,
		_lastFrames = {} :: { number },
		_maxSamples = 60,
		_stalls = 0,
		_report = nil :: ((msg: string, meta: any?) -> ())?,
	}, Watchdog) :: any
end

function Watchdog:setReporter(fn: (msg: string, meta: any?) -> ())
	self._report = fn
end

function Watchdog:beginFrame(_id: number)
	self._frameStart = os.clock()
end

function Watchdog:endFrame(_id: number, cycles: number)
	local dt = os.clock() - self._frameStart
	local ms = dt * 1000
	table.insert(self._lastFrames, ms)
	if #self._lastFrames > self._maxSamples then table.remove(self._lastFrames, 1) end
	if ms > Config.DIAG.stallMs then
		self._stalls += 1
		if self._report then
			self._report(`Emulator frame stalled {string.format("%.1f", ms)}ms (cycles={cycles})`, {
				kind = "stall", severity = "warn", category = "bug",
			})
		end
	end
end

function Watchdog:avgFrameMs(): number
	if #self._lastFrames == 0 then return 0 end
	local sum = 0
	for _, v in self._lastFrames do sum += v end
	return sum / #self._lastFrames
end

function Watchdog:fps(): number
	local avg = self:avgFrameMs()
	if avg <= 0 then return 0 end
	return 1000 / avg
end

function Watchdog:stalls(): number
	return self._stalls
end

return Watchdog
