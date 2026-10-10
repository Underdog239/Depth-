--!strict
--[[ Emulator/ROMLoader.luau

 Finds a ROM that has been baked into the place, since a Roblox client cannot
 read local files. Three supported shapes, checked in order:

   ReplicatedStorage.Assets.ROM     ModuleScript returning {string} (base64
                                    chunks, produced by web/rom-tool.html) or
                                    {number} (raw bytes)
   ReplicatedStorage.GBAROM         StringValue holding base64
   ReplicatedStorage.GBAROM (Folder) ordered StringValue chunks named 1, 2, 3...

 The web tool in web/ generates exactly these shapes, so the workflow is:
 drop a ROM in the tool -> download ROM.luau -> put it in src/Assets/ -> Rojo
 syncs it -> the client auto-loads on join.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Base64 = require(ReplicatedStorage.Shared.Base64)
local Util = require(ReplicatedStorage.Shared.Util)

local ROMLoader = {}

local MAX_ROM = 32 * 1024 * 1024

local function fromModule(inst: Instance): ({ number }?, string?)
	local ok, data = pcall(function()
		return require(inst :: any)
	end)
	if not ok or type(data) ~= "table" or #data == 0 then return nil, nil end
	local first = data[1]
	if type(first) == "string" then
		assert(#table.concat(data) <= math.ceil(MAX_ROM / 3) * 4, "Embedded ROM exceeds 32 MiB")
		local bytes = Base64.decodeToBuffer(table.concat(data))
		return bytes, "Assets.ROM (base64 chunks)"
	elseif type(first) == "number" then
		assert(#data <= MAX_ROM, "Embedded ROM exceeds 32 MiB")
		return Util.bytesToBuffer(data), "Assets.ROM (byte table)"
	end
	return nil, nil
end

local function fromFolder(folder: Instance): ({ number }?, string?)
	local parts = {}
	for _, child in folder:GetChildren() do
		if child:IsA("StringValue") then
			table.insert(parts, { tonumber(child.Name) or 0, child.Value })
		end
	end
	if #parts == 0 then return nil, nil end
	table.sort(parts, function(a, b) return a[1] < b[1] end)
	local joined = table.create(#parts)
	for i, p in parts do joined[i] = p[2] end
	assert(#table.concat(joined) <= math.ceil(MAX_ROM / 3) * 4, "Embedded ROM exceeds 32 MiB")
	return Base64.decodeToBuffer(table.concat(joined)), "GBAROM (chunk folder)"
end

--- Locate an embedded ROM. Returns (bytes, sourceName) or (nil, reason).
function ROMLoader.find(): ({ number }?, string?)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local mod = assets:FindFirstChild("ROM")
		if mod and mod:IsA("ModuleScript") then
			local bytes, name = fromModule(mod)
			if bytes then
				if buffer.len(bytes) > MAX_ROM then return nil, "embedded ROM exceeds 32 MiB" end
				return bytes, name
			end
		end
	end

	local holder = ReplicatedStorage:FindFirstChild("GBAROM")
	if holder then
		local bytes, name
		if holder:IsA("StringValue") then
			assert(#holder.Value <= math.ceil(MAX_ROM / 3) * 4, "Embedded ROM exceeds 32 MiB")
			bytes, name = Base64.decodeToBuffer(holder.Value), "GBAROM (StringValue)"
		elseif holder:IsA("Folder") then
			bytes, name = fromFolder(holder)
		end
		if bytes and buffer.len(bytes) > 0 then
			if buffer.len(bytes) > MAX_ROM then return nil, "embedded ROM exceeds 32 MiB" end
			return bytes, name
		end
	end

	return nil, "no embedded ROM found"
end

return ROMLoader
