#!/usr/bin/env python3
"""Boot both generated entry points against a non-Studio client with Source writes forbidden."""
import argparse
import base64
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
for artifact in [args.runtime, args.installer]:
    text = Path(artifact).read_text()
    assert not any(flag in text for flag in [':IsStudio(', ':IsRunning(', ':IsClient(']), 'Mode gate remains'
mock = r'''
local objects, tasks, warnings = {}, {}, {}
local waitTimeouts = {}
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
local ColorSequence={new=function(...) return {...} end}
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
function methods:WaitForChild(name, timeout)
 if timeout then table.insert(waitTimeouts, timeout) end
 return self:FindFirstChild(name)
end
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
services.RunService.IsRunning=function() error('Running flag must not be consulted') end
services.RunService.IsClient=function() error('Client flag must not be consulted') end
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
local function launch(...)
'''
checks=r'''
end
launch()
assert(playerGui:FindFirstChild('LuauGBA'),'Missing game UI')
local tabs, fields = {}, {}
for _,object in objects do
 if object.Name:sub(1,3)=='Tab' then tabs[object.Name]=object end
 if object.ClassName=='TextBox' then fields[object.PlaceholderText]=object end
end
local romBox=fields['Paste small ROM base64 here (up to 200,000 characters)']
assert(romBox and romBox.Visible,'Library must expose ROM loading')
assert(tabs.TabControls and tabs.TabSettings and tabs.TabSaves,'Missing navigation')
tabs.TabControls.Activated:Fire();assert(not romBox.Visible,'Inactive page leaked controls')
tabs.TabSaves.Activated:Fire();assert(fields['Battery save text'].Visible,'Save import must be reachable')
tabs.TabLibrary.Activated:Fire();assert(romBox.Visible,'Returning to library must restore ROM import')
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
playerGui.Parent=nil
local ok,err=pcall(launch)
assert(not ok and tostring(err):find('PlayerGui',1,true),'Missing PlayerGui must have an actionable error')
assert(waitTimeouts[#waitTimeouts]==10,'PlayerGui wait must be bounded')
assert(#objects==count,'Missing GUI mutated objects')
playerGui.Parent=player
services.Players.LocalPlayer=nil
assert(not pcall(launch),'Missing player/capabilities must fail')
assert(#objects==count,'Missing player attempt changed objects')
print('PASS: non-Studio client boots, demo advances, diagnostics scan tolerates no script Instance, duplicate launch is safe, missing capabilities reported with bounded GUI wait; no mode flags, Source access or script creation')
'''
with tempfile.TemporaryDirectory(prefix='depth-runtime-') as directory:
    for name in [args.runtime,args.installer]:
        script=Path(directory)/'boot.luau'
        script.write_text(mock+Path(name).read_text()+checks)
        subprocess.run([args.luau,str(script)],check=True)
        rom_checks = checks.replace('launch()\n', 'launch("' + base64.b64encode(bytes(192)).decode() + '")\n', 1)
        rom_checks = rom_checks.replace("local tabs, fields", "local loaded=false; for _,object in objects do if object.ClassName=='TextLabel' and object.Text and object.Text:find('ROM:',1,true) then loaded=true end end; assert(loaded,'Launcher ROM did not auto-load')\nlocal tabs, fields")
        script.write_text(mock+Path(name).read_text()+rom_checks)
        subprocess.run([args.luau,str(script)],check=True)
        script.write_text(mock+Path(name).read_text()+"\nend\nlocal count=#objects; assert(not pcall(launch,'!!!')); assert(#objects==count, 'Invalid launcher ROM created UI')\n")
        subprocess.run([args.luau,str(script)],check=True)
    # Exercise the browser-generated launcher's handoff into the real runtime.
    generated = Path(directory)/'rom.luau'
    subprocess.run(['node',str(Path(__file__).with_name('check_rom_tool.cjs')),str(generated)],check=True)
    script.write_text(mock+Path(args.runtime).read_text()+'''
end
local loadstring = function(source, name)
 assert(source == "verified runtime" and name == "Depth-runtime")
 return launch
end
game.HttpGet = function(_, url)
 assert(url:find('/installer/Depth-runtime.luau',1,true))
 return "verified runtime"
end
''' + Path(str(generated)+'.client.luau').read_text()+'''
local loaded=false
for _,object in objects do
 if object.ClassName=='TextLabel' and object.Text and object.Text:find('ROM:',1,true) then loaded=true end
end
assert(loaded, 'Browser launcher did not hand ROM to runtime')
print('PASS: browser-generated client launcher loads its ROM into actual bundled runtime with HTTP/compiler mocked')
''')
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
