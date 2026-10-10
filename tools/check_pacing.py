#!/usr/bin/env python3
"""Exercise the actual client frame callback with a deterministic work clock."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
source = (root / 'src/Client/init.client.luau').read_text()
callback = source.split('local function onFrame(dt: number)', 1)[1].split('\nRunService.RenderStepped:Connect', 1)[0]
mock = r'''
local time = 0
local os = {clock=function() return time end}
local Config = {FPS=59.7275}
local running,paused,menuOpen,focused = true,false,false,true
local frameIndex,emulationDebt,speedTime,speedFrames,gameFps = 0,0,0,0,0
local completedPixels = buffer.create(4)
local input = {mask=1}
local profiler = {beginSection=function() end,endSection=function() end,report=function() return {} end}
local watchdog = {beginFrame=function() end,endFrame=function() end}
local audio = {setActive=function() end,pump=function() end,status=function() return 'test' end}
local ui = {setMetrics=function() end,setAudioStatus=function() end,setRunning=function() end,setStatus=function() end}
local Diagnostics = {report=function(msg) error(msg) end}
local sampledFrame, sampledWork
local adaptive = {sliceMs=12,renderEvery=1,sample=function(_, frame, work) sampledFrame=frame; sampledWork=work end,sampleGameSpeed=function() end}
local pixels = buffer.create(4)
local remaining = 3
local cost = 3
local budgets,uploads = {},{}
local gba = {ppu={frameComplete=false,frameRendered=false,frame=0,dispcnt=0},frames=0,
 cpu={regs={[16]=0x08000000}},bus={cycles=0}}
function gba:setKeys(mask) assert(mask==1) end
function gba:framebuffer() return pixels end
function gba:runFrame(ms)
 table.insert(budgets,ms)
 local work = math.min(ms,remaining)
 time += work/1000; remaining -= work
 self.ppu.frameComplete = remaining <= 0.000001
 self.ppu.frameRendered = self.ppu.frameComplete and self.ppu.renderEvery==1
 if self.ppu.frameComplete then
  self.frames += 1; self.ppu.frame += 1; remaining=cost
  buffer.writeu32(pixels,0,self.frames)
 else buffer.writeu32(pixels,0,99) end
end
local renderer = {backend='mock',present=function(_,fb) table.insert(uploads,buffer.readu32(fb,0)) end}
'''
checks = r'''
local function reset(ms)
 time=0;frameIndex=0;emulationDebt=0;speedTime=0;speedFrames=0;gameFps=0
 budgets={};uploads={};gba.frames=0;gba.ppu.frame=0
 cost=ms;remaining=ms;running=true;paused=false;menuOpen=false;focused=true
 adaptive.renderEvery=1
end
reset(3)
onFrame(2/Config.FPS)
assert(gba.frames==2 and #budgets==2 and #uploads==1 and uploads[1]==2,'Catch-up must advance two frames and present the latest')
assert(math.abs(budgets[1]-12)<0.001 and math.abs(budgets[2]-9)<0.001 and time<=0.012,'Catch-up must share one deadline')
assert(math.abs(sampledFrame-2000/Config.FPS)<0.001 and math.abs(sampledWork-6)<0.001,'Adaptive budgeting must receive actual work separately from host interval')
reset(20)
onFrame(2/Config.FPS)
assert(gba.frames==0 and #uploads==0 and math.abs(time-0.012)<0.000001,'Incomplete frame must yield without presentation')
onFrame(2/Config.FPS)
assert(gba.frames==1 and uploads[1]==1 and buffer.readu32(pixels,0)==99,'Later partial work must not overwrite the presented completed frame')
reset(3)
onFrame(0.5/Config.FPS)
assert(#budgets==0,'Fast hosts must accumulate debt before emulation')
onFrame(0.5/Config.FPS)
assert(gba.frames==1,'Accumulated fractional debt must eventually run')
reset(3)
paused=true;onFrame(2/Config.FPS)
paused=false;menuOpen=true;onFrame(2/Config.FPS)
menuOpen=false;focused=false;onFrame(2/Config.FPS)
assert(#budgets==0 and emulationDebt==0,'Paused/menu/unfocused clients must not accumulate work')
reset(3);adaptive.renderEvery=3
onFrame(2/Config.FPS)
assert(gba.frames==2 and #uploads==0,'Skipped drawing must still advance the game without uploading stale pixels')
print('PASS: actual client callback catch-up, shared deadline, partial-frame preservation, fractional pacing and pause/focus behavior')
'''
with tempfile.TemporaryDirectory(prefix='depth-pacing-') as directory:
    path = Path(directory) / 'pacing.luau'
    path.write_text(mock + 'local function onFrame(dt: number)' + callback + checks)
    subprocess.run([args.luau, str(path)], check=True)
