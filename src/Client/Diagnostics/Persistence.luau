--!strict
--[[ Diagnostics/Persistence.luau

 Findings must survive a rejoin so the user can ask "what did it catch?"
 without re-running anything. Two backends:

   * ServerStore  -- DataStoreService (authoritative, cross-session)
   * SessionStore -- in-memory only (client fallback / tests)

 The client never talks to DataStore directly (that would be a vulnerability);
 it reaches the server through the DiagnosticsBridge RemoteFunction. ]]

local Persistence = {}

local ServerStore = {}
ServerStore.__index = ServerStore

function ServerStore.new(dataStoreName: string, key: string)
	return setmetatable({ _name = dataStoreName, _key = key, _ds = nil }, ServerStore) :: any
end

function ServerStore:_store()
	if self._ds then return self._ds end
	local ok, DSS = pcall(function() return game:GetService("DataStoreService") end)
	if not ok then return nil end
	local okGet, store = pcall(function() return DSS:GetDataStore(self._name) end)
	if not okGet then return nil end
	self._ds = store
	return store
end

function ServerStore:save(arr: { any }): boolean
	local store = self:_store()
	if not store then return false end
	local ok = pcall(function()
		store:SetAsync(self._key, arr)
	end)
	return ok
end

function ServerStore:load(): { any }
	local store = self:_store()
	if not store then return {} end
	local ok, data = pcall(function()
		return store:GetAsync(self._key)
	end)
	if ok and type(data) == "table" then return data end
	return {}
end

-- Session-only backend -----------------------------------------------------

local SessionStore = {}
SessionStore.__index = SessionStore

function SessionStore.new()
	return setmetatable({ _data = {} :: { any } }, SessionStore) :: any
end

function SessionStore:save(arr: { any }): boolean
	self._data = arr
	return true
end

function SessionStore:load(): { any }
	return self._data
end

--- Choose the best available backend for the current context.
function Persistence.auto(dataStoreName: string, key: string)
	local isServer = false
	local ok, rs = pcall(function() return game:GetService("RunService") end)
	if ok and rs then
		local okS, v = pcall(function() return rs:IsServer() end)
		isServer = okS and v or false
	end
	if isServer then
		return ServerStore.new(dataStoreName, key)
	end
	return SessionStore.new()
end

Persistence.ServerStore = ServerStore
Persistence.SessionStore = SessionStore
return Persistence
