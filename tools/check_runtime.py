#!/usr/bin/env python3
"""Boot both generated entry points against a non-Studio client with Source writes forbidden."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from build_runtime import bundle, compile_modules

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('place')
parser.add_argument('runtime')
parser.add_argument('installer')
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
modules, entry, edges = compile_modules(args.place)
assert sum(map(len, edges.values())) > 0
assert Path(args.runtime).read_text() == bundle(args.place), 'Runtime artifact is stale'
mock = r'''
local objects, tasks, warnings = {}, {}, {}
local running, client = true, true
local function signal()
 local callbacks = {}
 return {Connect=function(_,fn) callbacks[fn]=true;return {Disconnect=function() callbacks[fn]=nil end} end,
 Fire=function(_,...) for fn in callbacks do fn(...) end end}
end
local Enum=setmetatable({}, {__index=function(t,name)
 local category=setmetatable({}, {__index=function(c,key)
  local value={Name=key};rawset(c,key,value);return value
 end});rawset(t,name,category);return category
end})
local Vector2={new=function(x,y) return {X=x,Y=y} end,zero={X=0,Y=0}}
local UDim={new=function(scale,offset) return {Scale=scale,Offset=offset} end}
local UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
local Color3={new=function(...) return {...} end,fromRGB=function(...) return {...} end}
local warn=function(message) table.insert(warnings,tostring(message)) end
local task={}
function task.wait() coroutine.yield() end
function task.spawn(fn)
 local thread=coroutine.create(fn);table.insert(tasks,thread)
 local ok,err=coroutine.resume(thread);assert(ok,err);return thread
end
function task.delay(_,fn) return coroutine.create(fn) end
function task.cancel(thread) coroutine.close(thread) end
local methods={}
function methods:FindFirstChild(name)
 for _,object in objects do if object.Parent==self and object.Name==name and not object.destroyed then return object end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name),'Missing '..name) end
function methods:GetChildren()
 local out={};for _,object in objects do if object.Parent==self and not object.destroyed then table.insert(out,object) end end;return out
end
function methods:GetDescendants()
 local out={};for _,child in self:GetChildren() do table.insert(out,child);for _,grand in child:GetDescendants() do table.insert(out,grand) end end;return out
end
function methods:IsA(class) return self.ClassName==class end
function methods:Destroy() self.destroyed=true;self.Parent=nil end
function methods:GetPropertyChangedSignal(_) return signal() end
function methods:Play() self.IsPlaying=true end
function methods:Stop() self.IsPlaying=false end
function methods:CaptureFocus() end
local Instance={new=function(class)
 assert(class~='ModuleScript' and class~='LocalScript','Runtime tried creating script source container')
 local data={ClassName=class,Name=class,AbsoluteSize=Vector2.new(1024,768),IsLoaded=true,IsPlaying=false,
  Activated=signal(),InputBegan=signal()}
 local object=setmetatable({}, {__index=function(_,key)
  assert(key~='Source','Runtime tried reading protected script source')
  return methods[key] or data[key]
 end,__newindex=function(_,key,value)
  assert(key~='Source','Runtime tried writing protected script source');data[key]=value
 end})
 table.insert(objects,object);return object
end}
local services={}
for _,name in {'Players','ReplicatedStorage','SoundService','GuiService','RunService','UserInputService','AssetService','LogService','ScriptContext'} do
 services[name]={}
end
services.RunService.IsStudio=function() error('Studio probe must not be required in running client') end
services.RunService.IsRunning=function() return running end
services.RunService.IsClient=function() return client end
services.RunService.RenderStepped=signal();services.RunService.Heartbeat=signal()
local UIS=services.UserInputService
UIS.TouchEnabled=false;UIS.KeyboardEnabled=true
for _,name in {'InputBegan','InputEnded','InputChanged','WindowFocusReleased','WindowFocused','TextBoxFocused','GamepadDisconnected','LastInputTypeChanged'} do UIS[name]=signal() end
UIS.GetFocusedTextBox=function() return nil end
UIS.GetLastInputType=function() return Enum.UserInputType.Keyboard end
services.AssetService.CreateEditableImage=function() error('mock forces grid fallback') end
local player=Instance.new('Player')
local playerGui=Instance.new('PlayerGui');playerGui.Parent=player
services.Players.LocalPlayer=player
services.ReplicatedStorage=Instance.new('ReplicatedStorage')
local game={GetService=function(_,name) return assert(services[name],'Unexpected service '..name) end}
local function launch()
'''
checks=r'''
end
launch()
assert(playerGui:FindFirstChild('LuauGBA'),'Missing game UI')
local demo
for _,object in objects do
 if object.ClassName=='TextButton' and object.Text and object.Text:find('Run demo',1,true) then demo=object end
end
assert(demo,'Missing demo action');demo.Activated:Fire()
for _=1,24 do services.RunService.RenderStepped:Fire(1/60) end
for _,thread in tasks do
 if coroutine.status(thread)=='suspended' then local ok,err=coroutine.resume(thread);assert(ok,err) end
end
for _,object in objects do
 if object.ClassName=='TextLabel' and object.Text then
  assert(not object.Text:find('Frame error:',1,true),object.Text)
  assert(not object.Text:find('Emulation stopped:',1,true),object.Text)
 end
end
local count=#objects
launch()
assert(#objects==count,'Repeated launch created duplicate UI/audio')
client=false
assert(not pcall(launch),'Server execution should report unsupported context')
assert(#objects==count,'Server attempt changed client objects')
print('PASS: non-Studio client boots, demo advances, diagnostics scan tolerates no script Instance, duplicate launch is safe, server rejected; no Source access or script creation')
'''
with tempfile.TemporaryDirectory(prefix='depth-runtime-') as directory:
    for name in [args.runtime,args.installer]:
        script=Path(directory)/'boot.luau'
        script.write_text(mock+Path(name).read_text()+checks)
        subprocess.run([args.luau,str(script)],check=True)
    # Execute cached factories and actual emulator modules from the bundle.
    library=Path(directory)/'library.luau'
    library.write_text('local Enum = {KeyCode = setmetatable({}, {__index=function(_,key) return key end})}\n'
        'local game = {GetService=function() return {} end}\n'+bundle(args.place,launch=False))
    core=Path(directory)/'core.luau'
    core.write_text('''local bundle=require('./library')
local root='StarterPlayer/StarterPlayerScripts/GBAClient/'
local GBA=bundle.load(root..'Emulator/GBA')
assert(GBA==bundle.load(root..'Emulator/GBA'), 'Module cache identity changed')
local Demo=bundle.load(root..'Emulator/DemoROM')
local gba=GBA.new({rom=Demo.create()})
gba:runFrame()
assert(gba.ppu.frameComplete and gba.frames==1)
assert(not pcall(bundle.load,'missing'),'Missing module accepted')
print('PASS: bundled emulator completes demo frame; cache identity and missing-module errors verified')
''')
    subprocess.run([args.luau,str(core)],check=True)
print(f'Runtime bundler resolves {sum(map(len, edges.values()))} static requires across {len(modules)} factories')
