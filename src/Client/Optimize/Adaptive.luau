--!strict
--[[ Optimize/Adaptive.luau

 Keeps the emulator responsive on a real Roblox client. It watches measured FPS
 and frame time and decides, per frame, whether to:

   * present every produced frame (native)
   * skip presentation but keep emulating (catch-up)
   * lower render scale (fewer pixels to upload)
   * reduce emulated cycles per frame (slow-motion instead of freezing)

 All thresholds come from Config so behaviour is tunable in one place.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Adaptive = {}
Adaptive.__index = Adaptive

function Adaptive.new()
	return setmetatable({
		mode = "native",
		fpsSamples = {},
		frameSkip = 0,
		currentScale = Config.RENDER.scale,
		slowFrames = 0,
		fastFrames = 0,
	}, Adaptive) :: any
end

function Adaptive:sample(frameMs: number)
	table.insert(self.fpsSamples, frameMs)
	if #self.fpsSamples > 45 then table.remove(self.fpsSamples, 1) end
	local sum = 0
	for _, v in self.fpsSamples do sum += v end
	local avg = sum / #self.fpsSamples
	local fps = avg > 0 and 1000 / avg or 0

	if fps < Config.RENDER.minFps then
		self.slowFrames += 1
		self.fastFrames = 0
	elseif fps > Config.RENDER.targetFps * 0.95 then
		self.fastFrames += 1
		self.slowFrames = 0
	end

	-- React only after a sustained trend, to avoid oscillation.
	if self.slowFrames > 30 then
		self.mode = "catchup"
		if self.currentScale > 1 and Config.RENDER.autoScale then
			self.currentScale -= 1
			self.slowFrames = 0
		end
	elseif self.fastFrames > 120 then
		self.mode = "native"
		self.fastFrames = 0
	end
	return self.mode
end

function Adaptive:shouldPresent(frameIndex: number): boolean
	if self.mode == "native" then return true end
	-- catch-up: present every 2nd frame to buy back time
	return frameIndex % 2 == 0
end

return Adaptive
