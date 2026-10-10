--!strict
-- Sample monitor for the testing build. Computes levels for the UI; this
-- adapter does not provide audible playback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local AudioBridge = {}
AudioBridge.__index = AudioBridge

function AudioBridge.new(apu: any)
	local self = setmetatable({
		apu = apu,
		level = 0,
		peak = 0,
		samples = 0,
		batches = 0,
		lastBatch = 0,
	}, AudioBridge) :: any
	apu:setSink(function(batch) self:_onSamples(batch) end)
	return self
end

function AudioBridge:_onSamples(batch: { number })
	self.batches += 1
	self.lastBatch = #batch
	local sum = 0
	local peak = 0
	for _, v in batch do
		sum += v * v
		local a = v < 0 and -v or v
		if a > peak then peak = a end
	end
	self.samples += #batch
	local rms = #batch > 0 and math.sqrt(sum / #batch) / 128 or 0
	-- exponential smoothing keeps the meter readable instead of flickering
	self.level = self.level * 0.8 + math.min(rms, 1) * 0.2
	self.peak = math.max(peak / 128, self.peak * 0.92)
end

--- Pull any buffered samples into the meter (called from the frame loop).
function AudioBridge:pump()
	self.apu:flush()
end

function AudioBridge:stats()
	return {
		level = self.level,
		peak = self.peak,
		samples = self.samples,
		batches = self.batches,
	}
end

function AudioBridge:destroy()
	self.apu:setSink(nil)
end

return AudioBridge
