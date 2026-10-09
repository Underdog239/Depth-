--!strict
--[[ Diagnostics/Store.luau

 Ring buffer of Findings with dedup-by-symbol and occurrence counting.
 Pure data structure (no Roblox APIs) so it is trivially unit-testable and
 reusable on both client and server.
 ]]

local Classifier = require(script.Parent.Classifier)

export type Finding = Classifier.Finding

export type Store = {
	add: (self: Store, finding: Finding) -> Finding,
	get: (self: Store, symbol: string) -> Finding?,
	all: (self: Store) -> { Finding },
	count: (self: Store) -> number,
	countByCategory: (self: Store) -> { [string]: number },
	clear: (self: Store) -> (),
	toArray: (self: Store) -> { any },
	fromArray: (self: Store, arr: { any }) -> (),
}

local Store = {}
Store.__index = Store

function Store.new(maxEvents: number): Store
	return setmetatable({
		_max = maxEvents or 500,
		_bySymbol = {} :: { [string]: Finding },
		_order = {} :: { string },
	}, Store) :: any
end

--- Insert or increment. Returns the stored finding.
function Store:add(finding: Finding): Finding
	local existing = self._bySymbol[finding.symbol]
	if existing then
		existing.count += 1
		existing.lastSeen = finding.lastSeen
		if finding.severity == "fatal" or finding.severity == "error" then
			existing.severity = finding.severity
		end
		if finding.stack then existing.stack = finding.stack end
		return existing
	end
	self._bySymbol[finding.symbol] = finding
	table.insert(self._order, finding.symbol)
	-- evict oldest when over capacity
	while #self._order > self._max do
		local oldest = table.remove(self._order, 1)
		if oldest then self._bySymbol[oldest] = nil end
	end
	return finding
end

function Store:get(symbol: string): Finding?
	return self._bySymbol[symbol]
end

function Store:all(): { Finding }
	local out = table.create(#self._order)
	for i, sym in self._order do
		out[i] = self._bySymbol[sym]
	end
	return out
end

function Store:count(): number
	return #self._order
end

function Store:countByCategory(): { [string]: number }
	local counts = { error = 0, bug = 0, vulnerability = 0, unfinished = 0 }
	for _, sym in self._order do
		local f = self._bySymbol[sym]
		counts[f.category] = (counts[f.category] or 0) + 1
	end
	return counts
end

function Store:clear()
	table.clear(self._bySymbol)
	table.clear(self._order)
end

--- Serialize to a plain array (DataStore-safe: no mixed tables / functions).
function Store:toArray(): { any }
	local out = {}
	for _, sym in self._order do
		local f = self._bySymbol[sym]
		out[#out + 1] = {
			category = f.category,
			severity = f.severity,
			message = f.message,
			source = f.source,
			symbol = f.symbol,
			stack = f.stack,
			count = f.count,
			firstSeen = f.firstSeen,
			lastSeen = f.lastSeen,
		}
	end
	return out
end

function Store:fromArray(arr: { any })
	for _, raw in arr do
		self:add({
			id = raw.symbol,
			category = raw.category,
			severity = raw.severity,
			message = raw.message,
			source = raw.source,
			symbol = raw.symbol,
			stack = raw.stack,
			count = raw.count or 1,
			firstSeen = raw.firstSeen or 0,
			lastSeen = raw.lastSeen or 0,
		})
	end
end

return Store
