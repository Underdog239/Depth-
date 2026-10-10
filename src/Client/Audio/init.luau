--!strict
-- Public Roblox APIs cannot stream the APU's PCM buffer. An optional uploaded
-- 256 Hz square-wave loop approximates PSG channels 1/2; wave/noise/FIFO audio
-- is not synthesized by this adapter. It never claims full game-audio playback.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Audio = {}
Audio.__index = Audio
function Audio.new(apu)
	local self = setmetatable({apu=apu,level=0,peak=0,samples=0,batches=0,
		muted=false,active=false,lastUpdate=0,asset="",sounds={},testUntil=0},Audio)
	for i=1,3 do
		local sound = Instance.new("Sound")
		sound.Name = "DepthTone" .. i; sound.Looped = true; sound.Volume = 0
		sound.Parent = game:GetService("SoundService"); self.sounds[i] = sound
	end
	apu:setSink(function(batch) self:_onSamples(batch) end)
	if Config.AUDIO.squareAssetId ~= "" then self:setAsset(Config.AUDIO.squareAssetId) end
	return self
end
function Audio:_onSamples(batch)
	local sum,peak = 0,0
	for _,value in batch do sum += value*value; peak=math.max(peak,math.abs(value)) end
	self.samples += #batch; self.batches += 1
	self.level = self.level*0.8 + math.min(#batch>0 and math.sqrt(sum/#batch)/128 or 0,1)*0.2
	self.peak = math.max(peak/128,self.peak*0.92)
end
function Audio:setAsset(text)
	local id = text:match("^%s*(%d+)%s*$") or text:match("^rbxassetid://(%d+)$")
	if not id or #id > 20 or tonumber(id) == 0 then return "Enter the numeric ID of your uploaded 256 Hz square-wave loop" end
	self.asset = "rbxassetid://" .. id
	for _,sound in self.sounds do sound:Stop(); sound.SoundId=self.asset end
	return "Audio asset set. Press Test tone; the experience must have permission to use this asset."
end
function Audio:setMuted(muted)
	self.muted=muted
	if muted then for _,sound in self.sounds do sound:Stop() end end
end
function Audio:setActive(active)
	if active == self.active then return end
	self.active=active
	if not active then for i=1,2 do self.sounds[i]:Stop() end end
end
function Audio:stopTest() self.testUntil=0; self.sounds[3]:Stop() end
function Audio:testTone()
	if self.asset == "" then return "Upload Depth-square-256Hz.wav and enter its Roblox asset ID first" end
	if self.muted then return "Unmute audio before testing" end
	self.testUntil=os.clock()+1
	local sound=self.sounds[3]; sound.PlaybackSpeed=1; sound.Volume=0.2; sound:Play()
	return sound.IsLoaded and "Playing a one-second test tone" or "Audio loading; check asset permissions in Studio Output if silent"
end
function Audio:pump()
	self.apu:flush()
	local now=os.clock()
	if now>=self.testUntil and self.sounds[3].IsPlaying then self.sounds[3]:Stop() end
	if now-self.lastUpdate < 1/20 then return end
	self.lastUpdate=now
	local control=self.apu:read16(0x080)
	local right=bit32.band(control,7)/7
	local left=bit32.band(bit32.rshift(control,4),7)/7
	for i=1,2 do
		local sound,ch=self.sounds[i],self.apu.ch[i]
		local routing=math.max(bit32.band(control,bit32.lshift(1,7+i))~=0 and right or 0,
			bit32.band(control,bit32.lshift(1,11+i))~=0 and left or 0)
		local audible=self.active and not self.muted and self.asset~="" and self.apu.masterEnable and ch.enabled and routing>0
		if audible then
			sound.PlaybackSpeed=math.clamp((131072/math.max(2048-ch.freq,1))/256,0.05,20)
			sound.Volume=math.clamp(ch.envVol/15*routing*Config.AUDIO.master*0.3,0,1)
			if not sound.IsPlaying then sound:Play() end
		elseif sound.IsPlaying then sound:Stop() end
	end
end
function Audio:status()
	if self.asset=="" then return "Audio setup needed: no waveform asset. Full PCM playback is unavailable on Roblox clients." end
	if not self.sounds[3].IsLoaded then return "Audio asset loading or inaccessible. Use Test tone and check experience permissions." end
	return self.muted and "Muted" or "Approximate square-channel audio ready. PCM music, wave and noise are not played."
end
function Audio:stats() return {level=self.level,peak=self.peak,samples=self.samples,batches=self.batches} end
function Audio:destroy()
	self.apu:setSink(nil)
	for _,sound in self.sounds do sound:Destroy() end
end
return Audio
