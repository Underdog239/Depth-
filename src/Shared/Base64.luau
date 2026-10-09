--!strict
--[[ Shared/Base64.luau -- dependency-free base64 for ROM/save transfer.
     Roblox clients cannot read local files, so ROMs are pasted as base64 text
     and decoded here (or supplied programmatically as a byte array). ]]

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE: { [number]: number } = {}
for i = 1, #ALPHABET do
	DECODE[string.byte(ALPHABET, i)] = i - 1
end

function Base64.encode(bytes: { number }): string
	local out = table.create(math.ceil(#bytes / 3) * 4)
	local i = 1
	while i + 2 <= #bytes do
		local n = bytes[i] * 0x10000 + bytes[i + 1] * 0x100 + bytes[i + 2]
		out[#out + 1] = string.sub(ALPHABET, n // 0x40000 % 64 + 1, n // 0x40000 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n // 0x1000 % 64 + 1, n // 0x1000 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n // 0x40 % 64 + 1, n // 0x40 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n % 64 + 1, n % 64 + 1)
		i += 3
	end
	local rem = #bytes - i + 1
	if rem == 1 then
		local n = bytes[i] * 0x10000
		out[#out + 1] = string.sub(ALPHABET, n // 0x40000 % 64 + 1, n // 0x40000 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n // 0x1000 % 64 + 1, n // 0x1000 % 64 + 1)
		out[#out + 1] = "="
		out[#out + 1] = "="
	elseif rem == 2 then
		local n = bytes[i] * 0x10000 + bytes[i + 1] * 0x100
		out[#out + 1] = string.sub(ALPHABET, n // 0x40000 % 64 + 1, n // 0x40000 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n // 0x1000 % 64 + 1, n // 0x1000 % 64 + 1)
		out[#out + 1] = string.sub(ALPHABET, n // 0x40 % 64 + 1, n // 0x40 % 64 + 1)
		out[#out + 1] = "="
	end
	return table.concat(out)
end

function Base64.decode(text: string): { number }
	local out: { number } = {}
	local n = #text
	local i = 1
	while i <= n do
		local c1 = DECODE[string.byte(text, i)]
		local c2 = DECODE[string.byte(text, i + 1) or 0]
		local c3 = DECODE[string.byte(text, i + 2) or 0]
		local c4 = DECODE[string.byte(text, i + 3) or 0]
		if c1 == nil then break end
		out[#out + 1] = c1 * 4 + (c2 or 0) // 16
		if c3 ~= nil then
			out[#out + 1] = ((c2 or 0) % 16) * 16 + c3 // 4
		end
		if c4 ~= nil then
			out[#out + 1] = (c3 % 4) * 64 + c4
		end
		i += 4
	end
	return out
end

return Base64
