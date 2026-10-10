--!nocheck
-- Observational sandbox probe, not a device performance guarantee.
local GBA=require("../Client/Emulator/GBA")
local Demo=require("../Client/Emulator/DemoROM")
for _,budget in {4,8} do
	local gba=GBA.new({rom=Demo.create()})
	local durations={}
	for _=1,90 do
		local started=os.clock()
		gba:runFrame(budget)
		table.insert(durations,(os.clock()-started)*1000)
	end
	table.sort(durations)
	local sum=0
	for _,duration in durations do sum+=duration end
	print(string.format("budget=%dms mean=%.2fms p95=%.2fms max=%.2fms emulatedFrames=%d slices=%d",
		budget,sum/#durations,durations[math.ceil(#durations*0.95)],durations[#durations],gba.frames,#durations))
end
