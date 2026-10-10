--!strict
-- Bound work in wall-clock milliseconds. Screen scaling does not reduce CPU work.
local Adaptive = {}
Adaptive.__index = Adaptive
function Adaptive.new(touch: boolean?)
	local maximum = touch and 4 or 8
	return setmetatable({ mode = "balanced", maximum = maximum, sliceMs = maximum,
		slowFrames = 0, fastFrames = 0, averageMs = 16.7, presentEvery = 1 }, Adaptive)
end
function Adaptive:setLowPower(enabled: boolean)
	self.mode = enabled and "battery" or "balanced"
	self.sliceMs = math.min(self.sliceMs, enabled and 3 or self.maximum)
	self.presentEvery = enabled and 2 or 1
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
