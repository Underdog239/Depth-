#!/usr/bin/env python3
"""Exercise real input/audio adapters with deterministic Roblox service mocks."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--luau',default='luau')
args=parser.parse_args()
mock=r'''
local checks=0
local function check(name,value) assert(value,name);checks+=1;print('PASS '..name) end
local function signal()
 local callbacks={}
 return {Connect=function(_,fn)
  callbacks[fn]=true
  return {Disconnect=function() callbacks[fn]=nil end}
 end,Fire=function(_,...) for fn in callbacks do fn(...) end end}
end
local Enum=setmetatable({}, {__index=function(t,k)
 local values=setmetatable({}, {__index=function(tab,name)
  local value={Name=name};rawset(tab,name,value);return value
 end});rawset(t,k,values);return values
end})
local clock=10
local os={clock=function() return clock end}
local delayed={}
local task={delay=function(_,fn) table.insert(delayed,fn) end}
local typeof=function(value) return type(value)=='table' and value._input and 'InputObject' or type(value) end
local UIS={focused=nil}
for _,name in {'InputBegan','InputEnded','InputChanged','WindowFocusReleased','TextBoxFocused','GamepadDisconnected'} do UIS[name]=signal() end
function UIS:GetFocusedTextBox() return self.focused end
local soundService={}
local game={GetService=function(_,name)
 if name=='UserInputService' then return UIS end
 if name=='SoundService' then return soundService end
 error('Unexpected service '..name)
end}
local Instance={new=function(class)
 assert(class=='Sound')
 local sound={IsPlaying=false,IsLoaded=true}
 function sound:Play() self.IsPlaying=true end
 function sound:Stop() self.IsPlaying=false end
 function sound:Destroy() self.destroyed=true;self.IsPlaying=false end
 return sound
end}
local function event(key,kind)
 return {_input=true,KeyCode=Enum.KeyCode[key],UserInputType=Enum.UserInputType[kind or 'Keyboard']}
end
'''
config=(ROOT/'src/Shared/Config.luau').read_text()
state=(ROOT/'src/Client/Input/State.luau').read_text()
input_source=(ROOT/'src/Client/Input/init.luau').read_text().replace('local Config = require(game:GetService("ReplicatedStorage").Shared.Config)','').replace('local State = require(script.State)','')
audio=(ROOT/'src/Client/Audio/init.luau').read_text().replace('local Config = require(game:GetService("ReplicatedStorage").Shared.Config)','')
checks=r'''
local input=Input.new()
UIS.InputBegan:Fire(event('Z'),false)
UIS.InputBegan:Fire(event('ButtonA','Gamepad1'),false)
UIS.InputEnded:Fire(event('Z'))
check('keyboard release preserves controller hold',input.mask==1)
UIS.InputEnded:Fire(event('ButtonA','Gamepad1'))
check('distinct ended InputObjects release binding',input.mask==0)
input:touch('finger',4,true)
UIS.InputEnded:Fire(event('Unknown','Touch'))
check('unrelated touch release preserves held touch',input.mask==16)
input:touch('finger',nil,false)
check('touch release clears mask',input.mask==0)
local stick=event('Thumbstick1','Gamepad1');stick.Position={X=-1,Y=1}
UIS.InputChanged:Fire(stick)
check('event-driven stick direction',input.mask==96)
UIS.GamepadDisconnected:Fire()
check('controller disconnect clears stick',input.mask==0)
UIS.focused={};UIS.InputBegan:Fire(event('Z'),false)
check('typing cannot press GBA keys',input.mask==0)
UIS.focused=nil
local message
input:beginMapping(0,function(text) message=text end)
UIS.InputBegan:Fire(event('Q'),false)
UIS.InputBegan:Fire(event('Q'),false)
check('keyboard remap takes effect',input.mask==1 and message~=nil and input.keyboard[Enum.KeyCode.Z]==nil)
UIS.WindowFocusReleased:Fire()
check('window blur releases remapped controls',input.mask==0)
input:beginMapping(1,function(text) message=text end)
UIS.InputBegan:Fire(event('ButtonX','Gamepad1'),false)
check('controller remap uses controller map',input.gamepad[Enum.KeyCode.ButtonX]==1 and input.keyboard[Enum.KeyCode.ButtonX]==nil)
input:resetBindings()
check('restore defaults',input.keyboard[Enum.KeyCode.Z]==0 and input.gamepad[Enum.KeyCode.ButtonB]==1)
input:setEnabled(false);UIS.InputBegan:Fire(event('Z'),false)
check('menu disables gameplay input',input.mask==0)
input:destroy()
local apu={masterEnable=true,ch={{enabled=true,freq=1536,envVol=15},{enabled=false,freq=0,envVol=0}}}
function apu:setSink(sink) self.sink=sink end
function apu:flush() end
function apu:read16(_) return 0x1177 end
local output=Audio.new(apu)
check('missing asset visibly reported',output:status():find('setup needed')~=nil)
output:setAsset('not an id')
check('invalid audio asset rejected',output.asset=='')
output:setAsset('12345');output:setActive(true);output:pump()
check('square channel uses uploaded loop at correct pitch',output.sounds[1].IsPlaying and output.sounds[1].PlaybackSpeed==1)
check('disabled channel stays silent',not output.sounds[2].IsPlaying)
output:setMuted(true)
check('mute stops all audio',not output.sounds[1].IsPlaying)
output:setMuted(false);output:setActive(false);output:testTone()
check('test tone works while gameplay paused',output.sounds[3].IsPlaying and not output.sounds[1].IsPlaying)
clock+=2;output:pump()
check('test tone stops after one second',not output.sounds[3].IsPlaying)
output:destroy()
check('adapter cleanup detaches sink and destroys sounds',apu.sink==nil and output.sounds[1].destroyed)
print(checks..' adapter checks passed (mock services, not real engine/audio)')
'''
source=mock+'\nlocal Config=(function()\n'+config+'\nend)()\nlocal State=(function()\n'+state+'\nend)()\nlocal Input=(function()\n'+input_source+'\nend)()\nlocal Audio=(function()\n'+audio+'\nend)()\n'+checks
with tempfile.TemporaryDirectory(prefix='depth-adapters-') as directory:
    path=Path(directory)/'check.luau';path.write_text(source)
    subprocess.run([args.luau,str(path)],check=True)
