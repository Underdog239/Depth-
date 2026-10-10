--!strict
-- Bound work in wall-clock milliseconds. Screen scaling does not reduce CPU work.
local Adaptive = {}
Adaptive.__index = Adaptive
function Adaptive.new(touch: boolean?)
	local initial, maximum = touch and 8 or 12, touch and 10 or 14
	return setmetatable({ mode = "balanced", initial = initial, maximum = maximum, sliceMs = initial,
		slowFrames = 0, fastFrames = 0, averageMs = 16.7, presentEvery = 1,
		renderEvery = 1, recoverySeconds = 0 }, Adaptive)
end
function Adaptive:setLowPower(enabled: boolean)
	self.mode = enabled and "battery" or "balanced"
	self.sliceMs = enabled and math.min(self.sliceMs, 3) or self.initial
	self.presentEvery = enabled and 2 or 1
	self.renderEvery = enabled and 2 or 1
	self.recoverySeconds = 0
end
-- Drop drawing work when emulation falls behind. Game logic, interrupts and
-- input keep their normal clock; this differs from merely hiding uploaded frames.
function Adaptive:sampleGameSpeed(fps: number)
	if fps < 45 then
		self.renderEvery = math.min(3, self.renderEvery + 1)
		self.recoverySeconds = 0
	elseif fps >= 57 then
		self.recoverySeconds += 1
		if self.recoverySeconds >= 3 then
			self.renderEvery = math.max(self.mode == "battery" and 2 or 1, self.renderEvery - 1)
			self.recoverySeconds = 0
		end
	else self.recoverySeconds = 0 end
end
function Adaptive:sample(frameMs: number)
	self.averageMs += (math.clamp(frameMs, 1, 250) - self.averageMs) * 0.05
	if self.averageMs > 35 then
		self.slowFrames += 1; self.fastFrames = 0
	elseif self.averageMs < 20 then
		self.fastFrames += 1; self.slowFrames = 0
	else self.slowFrames, self.fastFrames = 0, 0 end
	if self.slowFrames >= 20 then
		self.sliceMs = math.max(2, self.sliceMs - 1)
		self.presentEvery = 2
		self.slowFrames = 0
	elseif self.fastFrames >= 180 then
		self.sliceMs = math.min(self.mode == "battery" and 3 or self.maximum, self.sliceMs + 1)
		self.presentEvery = self.mode == "battery" and 2 or 1
		self.fastFrames = 0
	end
end
function Adaptive:shouldPresent(frameIndex: number): boolean
	return frameIndex % self.presentEvery == 0
end
return Adaptive
