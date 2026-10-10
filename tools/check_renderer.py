#!/usr/bin/env python3
"""Exercise the real renderer's initial display and native-to-grid recovery."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
mock = r'''
local checks=0
local function check(name,value) assert(value,name); checks+=1; print('PASS '..name) end
local Config={SCREEN_W=240,SCREEN_H=160,RENDER={scale=2,mode='native'}}
local Logger={info=function() end,warn=function() end}
local now=10
local os={clock=function() return now end}
local Color3={new=function(r,g,b) return {r=r*255,g=g*255,b=b*255} end,
 fromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
local Vector2={zero={},new=function(x,y) return {X=x,Y=y} end}
local UDim2={fromScale=function(...) return {...} end}
local Enum={ResamplerMode={Pixelated='Pixelated'}}
local Content={fromObject=function(image) return image end}
local objects={}
local Instance={new=function(class)
 local object={ClassName=class,BackgroundColor3=Color3.fromRGB(163,163,163)}
 function object:Destroy() self.destroyed=true;self.Parent=nil end
 table.insert(objects,object);return object
end}
local allocation='ok'
local failWrite=false
local images={}
local AssetService={CreateEditableImage=function()
 if allocation=='throw' then error('image allocation denied') end
 if allocation=='nil' then return nil end
 local image={writes=0}
 function image:WritePixelsBuffer(_,_,fb)
  self.writes+=1
  if failWrite then error('image writes denied') end
  self.last=fb
 end
 function image:Destroy() self.destroyed=true end
 table.insert(images,image);return image
end}
local game={GetService=function(_,name) assert(name=='AssetService');return AssetService end}
local function black(color) return color.r==0 and color.g==0 and color.b==0 end
'''
source=(ROOT/'src/Client/Render/init.luau').read_text()
source=source.replace('local ReplicatedStorage = game:GetService("ReplicatedStorage")','')
source=source.replace('local Config = require(ReplicatedStorage.Shared.Config)','')
source=source.replace('local Logger = require(ReplicatedStorage.Shared.Logger)','')
checks=r'''
local pixels=buffer.create(240*160*4)
for i=0,240*160-1 do buffer.writeu32(pixels,i*4,0xFF00FF00) end
allocation='throw'
local denied=Renderer.new({})
check('allocation denial selects grid',denied.backend=='grid')
for _,cell in denied.cells do check('initial fallback pixel is black',black(cell.BackgroundColor3));break end
denied:present(pixels,true)
check('fallback displays actual green framebuffer',denied.cells[1].BackgroundColor3.g==255 and denied.cells[1].BackgroundColor3.r==0)
denied:destroy()
allocation='nil'
local unavailable=Renderer.new({})
check('nil image allocation selects grid',unavailable.backend=='grid')
unavailable:destroy()
allocation='ok'
local native=Renderer.new({})
local image=native.editableImage
local label=native.imageLabel
native:present(pixels,true)
check('native upload uses actual framebuffer',native.backend=='editableimage' and image.last==pixels)
failWrite=true
local ok,err=pcall(function() native:present(pixels) end)
check('native upload failure recovers instead of throwing',ok)
check('native upload failure switches backend',native.backend=='grid')
check('failed native resources released',image.destroyed and label.destroyed)
check('recovery presents same frame immediately',native.cells[1].BackgroundColor3.g==255 and native.cells[1].BackgroundColor3.r==0)
local writes=image.writes
now+=1
native:present(pixels)
check('later frames do not retry broken native backend',image.writes==writes)
native:destroy()
check('renderer cleanup destroys container',native.container.destroyed)
print(checks..' renderer checks passed (mock services, not Roblox visual acceptance)')
'''
with tempfile.TemporaryDirectory(prefix='depth-render-') as directory:
    path=Path(directory)/'check.luau'
    path.write_text(mock+'\nlocal Renderer=(function()\n'+source+'\nend)()\n'+checks)
    subprocess.run([args.luau,str(path)],check=True)
