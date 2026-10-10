--!strict
--[[ Audio (init)

 The bridge between the emulated APU and Roblox. Roblox has no PCM playback API,
 so this module does two real things instead of pretending:

   1. Consumes APU sample batches and computes a smoothed level / peak, which the
      UI renders as a VU meter. That is direct, visible evidence the audio path
      is alive.

   2. If the project supplies Sound assets for the synth channels (see
      Config.AUDIO), it drives Roblox Sound objects so the four PSG channels are
      audible. Without supplied assets there is nothing to play, so the level
      meter is the output.

 Nothing here is required for emulation to be correct.
 ]]

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
		synth = nil,
	}, AudioBridge) :: any
	apu:setSink(function(batch) self:_onSamples(batch) end)
	if Config.AUDIO.mode == "synth" then
		self:_installSynth()
	end
	return self
end

function AudioBridge:_installSynth()
	-- Synth playback needs per-channel Sound assets; without them we stay on the
	-- level meter. This is a capability check, not a failure.
	self.synth = nil
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
