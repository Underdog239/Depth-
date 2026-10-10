--!nocheck
local State = require("../Client/Input/State")
local Adaptive = require("../Client/Optimize/Adaptive")
local Apu = require("../Client/Emulator/Hardware/Apu")
local Layout = require("../Client/UI/Layout")
local checks=0
local function check(name,condition)
	assert(condition,name)
	checks+=1; print("PASS "..name)
end
local input=State.new()
input:set("finger1",0,true);input:set("finger2",0,true);input:set("key",4,true)
check("independent sources combine",input:mask(0.25)==0x11)
input:set("finger1",nil,false)
check("releasing one source preserves another",input:mask(0.25)==0x11)
input:set("finger2",nil,false)
check("last release removes the button",input:mask(0.25)==0x10)
input.x,input.y=-0.8,0.8
check("analog up and left mapping",input:mask(0.25)==0x70)
input:clear();input.x,input.y=0.2,-0.2
check("stick deadzone",input:mask(0.25)==0)
check("out-of-range button rejected",not pcall(function() input:set("bad",10,true) end))
input:set("touch",9,true);input:clear()
check("focus release clears all input sources",input:mask(0.25)==0)
local phone,pc=Adaptive.new(true),Adaptive.new(false)
check("balanced profiles give emulation more bounded work",phone.sliceMs==12 and pc.sliceMs==14)
for _=1,400 do phone:sample(60,60);pc:sample(60,60) end
check("slow devices reduce bounded work",phone.sliceMs==6 and pc.sliceMs==6)
check("slow devices throttle presentations",not pc:shouldPresent(1) and pc:shouldPresent(2))
for _=1,3000 do pc:sample(16,12) end
check("stable performance recovers desktop budget",pc.sliceMs==18 and pc.presentEvery==1)
pc:setLowPower(true)
for _=1,1000 do pc:sample(16,12) end
check("battery mode remains capped",pc.sliceMs<=3 and not pc:shouldPresent(1))
pc:setLowPower(false)
check("leaving battery mode restores work immediately",pc.sliceMs==14)
for _=1,1500 do pc:sample(16,12) end
check("balanced mode restores headroom",pc.sliceMs==18)
pc:sampleGameSpeed(20);pc:sampleGameSpeed(20)
check("slow emulation reduces raster work",pc.renderEvery==3)
for _=1,9 do pc:sampleGameSpeed(60) end
check("drawing quality recovers after sustained game speed",pc.renderEvery==1)
pc:setLowPower(true)
for _=1,9 do pc:sampleGameSpeed(60) end
check("battery drawing remains bounded",pc.renderEvery==2)
local tablet = Adaptive.new(true)
for _=1,600 do tablet:sample(50,10) end
check("20 FPS host cannot starve inexpensive emulator work",tablet.sliceMs==16)
for _=1,600 do tablet:sample(33.3,10) end
check("30 FPS host retains the tablet budget",tablet.sliceMs==16)
for _=1,600 do tablet:sample(60,40) end
check("real work overruns still reduce the tablet budget",tablet.sliceMs==6)
local apu=Apu.new()
for i=1,4096 do apu.buffer[i]=i end
local first=apu:readSamples(3)
check("audio partial drain preserves FIFO ordering",#first==3 and first[1]==1 and first[3]==3 and apu.buffer[1]==4)
local rest=apu:readSamples()
check("audio full drain clears buffer",#rest==4093 and rest[#rest]==4096 and #apu.buffer==0)
check("empty audio drain safe",#apu:readSamples()==0)
apu.buffer={1,2,3}
check("negative sample count does not mutate",#apu:readSamples(-1)==0 and #apu.buffer==3)
for _, device in {{320,568,true},{390,844,true},{844,354,true},{768,1024,true},{1024,732,true},{1366,732,false}} do
	local w,h,touch=device[1],device[2],device[3]
	local geometry=Layout.compute(w,h,touch)
	check("layout fits "..w.."x"..h,geometry.screenWidth>0 and geometry.screenWidth<=w
		and geometry.screenY>=90 and geometry.screenY+geometry.screenHeight<=h-28
		and geometry.menuWidth<=w-24 and geometry.menuHeight<=h-94)
end
print(string.format("%d client feature checks passed",checks))
