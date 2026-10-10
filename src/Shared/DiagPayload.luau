--!strict
-- Only bounded primitive fields cross the diagnostics persistence boundary.
local Payload = {}
local CATEGORIES = {error = true, bug = true, vulnerability = true, unfinished = true}
local SEVERITIES = {info = true, warn = true, error = true, fatal = true}
local function text(value: any, max: number): string
	return type(value) == "string" and value:sub(1, max) or ""
end
local function number(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return fallback end
	return math.clamp(value, 0, 1e12)
end
function Payload.sanitize(raw: any): any
	if type(raw) ~= "table" or type(raw.category) ~= "string" or not CATEGORIES[raw.category] then return nil end
	if type(raw.message) ~= "string" or type(raw.symbol) ~= "string" then return nil end
	return {message = text(raw.message, 512), symbol = text(raw.symbol, 512),
		category = raw.category, severity = type(raw.severity) == "string" and SEVERITIES[raw.severity] and raw.severity or "info",
		source = text(raw.source, 128), stack = text(raw.stack, 2048),
		count = math.max(1, number(raw.count, 1)), firstSeen = number(raw.firstSeen, 0), lastSeen = number(raw.lastSeen, 0)}
end
function Payload.merge(existing: {any}, incoming: {any}, limit: number): {any}
	local map, order = {}, {}
	for _, list in {existing, incoming} do
		for i = 1, math.min(#list, limit) do
			local f = Payload.sanitize(list[i])
			if f then
				local old = map[f.symbol]
				if old then f.count = math.max(old.count, f.count)
				else table.insert(order, f.symbol) end
				map[f.symbol] = f
			end
		end
	end
	local out = {}
	for i = math.max(1, #order - limit + 1), #order do table.insert(out, map[order[i]]) end
	return out
end
return Payload
