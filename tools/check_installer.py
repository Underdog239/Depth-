"""Compare installer output to Rojo XML and exercise failure paths with Luau mocks."""
import argparse
import tempfile
import json
import xml.etree.ElementTree as ET
from pathlib import Path
import subprocess
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('place')
parser.add_argument('installer')
parser.add_argument('--luau', default='luau')
args = parser.parse_args()
xml=ET.parse(args.place).getroot()
expected=[]
def visit(item,path):
    name=item.findtext("./Properties/*[@name='Name']")
    path=path+'.'+name if path else name
    source=item.find("./Properties/*[@name='Source']")
    expected.append('{path=%s, class=%s, source=%s}' % (json.dumps(path),json.dumps(item.attrib['class']),json.dumps(source.text,ensure_ascii=False) if source is not None else 'nil'))
    for c in item.findall('Item'): visit(c,path)
for item in xml.findall('Item'): visit(item,'')
mock=r'''
local services, objects = {}, {}
local studio, running, failSource, failParent = true, false, false, false
local methods = {}
function methods:FindFirstChild(name)
    for _, child in ipairs(objects) do
        if child.Parent == self and child.Name == name then return child end
    end
end
function methods:FindFirstChildOfClass(class)
    for _, child in ipairs(objects) do
        if child.Parent == self and child.ClassName == class then return child end
    end
end
function methods:GetFullName()
    return self.Parent and self.Parent:GetFullName() .. '.' .. self.Name or self.Name
end
function methods:Destroy()
    for _, child in ipairs(objects) do
        if child.Parent == self then child:Destroy() end
    end
    self.Parent = nil
    self.destroyed = true
end
local Instance = {}
function Instance.new(class)
    local data = {ClassName=class}
    local obj = setmetatable({}, {
        __index = function(_, key) return methods[key] or data[key] end,
        __newindex = function(_, key, value)
            if failSource and key == 'Source' then error('source write failed') end
            if failParent and key == 'Parent' and value == services.StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts') then error('parent failed') end
            data[key] = value
        end,
    })
    table.insert(objects, obj)
    return obj
end
local game = {}
function game:GetService(name)
    if name == 'RunService' then return {
        IsStudio = function() return studio end,
        IsClient = function() return false end,
        IsRunning = function() return running end,
    } end
    return assert(services[name], name)
end
local function reset()
    services, objects = {}, {}
    studio, running, failSource, failParent = true, false, false, false
    for _, name in ipairs({'ReplicatedStorage', 'StarterPlayer'}) do
        local obj = Instance.new(name)
        obj.Name = name
        services[name] = obj
    end
    local scripts = Instance.new('StarterPlayerScripts')
    scripts.Name = 'StarterPlayerScripts'
    scripts.Parent = services.StarterPlayer
end
local function install()
'''
checks=r'''
end
reset()
install()
local count = 0
for _, definition in ipairs(expected) do
    local found
    for _, object in ipairs(objects) do
        if object:GetFullName() == definition.path then found = object break end
    end
    assert(found, definition.path)
    assert(found.ClassName == definition.class, definition.path .. ' class')
    assert(found.Source == definition.source, definition.path .. ' source')
    count += 1
end
assert(#objects == count, 'unexpected instances')
local before = #objects
assert(not pcall(install), 'reinstallation must reject collision')
assert(#objects == before, 'collision changed tree')
reset()
local unrelated = Instance.new('Folder')
unrelated.Name = 'GBAClient'
unrelated.Parent = services.StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts')
before = #objects
assert(not pcall(install), 'later destination collision must fail')
assert(#objects == before and unrelated.Parent == services.StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts'))
for _, mode in ipairs({'outsideStudio', 'playing', 'source', 'parent'}) do
    reset()
    before = #objects
    studio = mode ~= 'outsideStudio'
    running = mode == 'playing'
    failSource = mode == 'source'
    failParent = mode == 'parent'
    assert(not pcall(install), mode .. ' must fail')
    if mode == 'outsideStudio' or mode == 'playing' then
        assert(#objects == before, mode .. ' mutated tree')
    else
        for i=before+1,#objects do
            assert(objects[i].destroyed and objects[i].Parent == nil, mode .. ' cleanup')
        end
    end
end
print('PASS: full XML hierarchy/source fidelity (' .. count .. ' instances), collisions, execution-context guards, and failure cleanup')
'''
script='local expected = {\n'+',\n'.join(expected)+'\n}\n'+mock+Path(args.installer).read_text()+checks
with tempfile.TemporaryDirectory(prefix='depth-installer-') as temporary:
    smoke = Path(temporary) / 'smoke.luau'
    smoke.write_text(script)
    subprocess.run([args.luau, str(smoke)], check=True)
