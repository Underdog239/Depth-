--!strict
-- Findings are isolated by player. Requests update a bounded cache; persistence
-- is coalesced so every client push does not consume a DataStore write.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage.Shared.Config)
local Payload = require(ReplicatedStorage.Shared.DiagPayload)
local store
if Config.DIAG.persist then
	pcall(function() store = game:GetService("DataStoreService"):GetDataStore(Config.DIAG.dataStoreName) end)
end
local sessions = {}
local function session(player)
	local id = player.UserId
	if sessions[id] then return sessions[id] end
	local data = {}
	if store then
		local ok, value = pcall(function() return store:GetAsync("player:" .. id) end)
		if ok and type(value) == "table" then data = Payload.merge({}, value, Config.DIAG.maxEvents) end
	end
	-- Another request may have completed while GetAsync yielded.
	if not sessions[id] then sessions[id] = {findings = data, dirty = false, revision = 0} end
	return sessions[id]
end
local function save(id, state)
	if not store or not state.dirty or state.saving then return end
	state.saving = true
	local revision, snapshot = state.revision, state.findings
	local ok = pcall(function()
		store:UpdateAsync("player:" .. id, function(old)
			return Payload.merge(type(old) == "table" and old or {}, snapshot, Config.DIAG.maxEvents)
		end)
	end)
	state.saving = false
	if ok and state.revision == revision then state.dirty = false end
end
local remotes = Instance.new("Folder")
remotes.Name = "GBADiagRemotes"
remotes.Parent = ReplicatedStorage
local push = Instance.new("RemoteFunction")
push.Name = "PushFindings"
push.Parent = remotes
local get = Instance.new("RemoteFunction")
get.Name = "GetFindings"
get.Parent = remotes
local lastPush, lastGet = {}, {}
push.OnServerInvoke = function(player, payload)
	local now = os.clock()
	if lastPush[player] and now - lastPush[player] < 5 then return false end
	lastPush[player] = now
	if type(payload) ~= "table" or #payload > Config.DIAG.maxEvents then return false end
	local state = session(player)
	state.findings = Payload.merge(state.findings, payload, Config.DIAG.maxEvents)
	state.dirty = true
	state.revision += 1
	return true
end
get.OnServerInvoke = function(player)
	local now = os.clock()
	if lastGet[player] and now - lastGet[player] < 5 then return {} end
	lastGet[player] = now
	return session(player).findings
end
task.spawn(function()
	while true do
		task.wait(30)
		for id, state in sessions do task.spawn(save, id, state) end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	local state = sessions[player.UserId]
	if state then save(player.UserId, state) end
	sessions[player.UserId] = nil
	lastPush[player], lastGet[player] = nil, nil
end)
game:BindToClose(function()
	local remaining = 0
	for id, state in sessions do
		remaining += 1
		task.spawn(function() save(id, state); remaining -= 1 end)
	end
	local deadline = os.clock() + 25
	while remaining > 0 and os.clock() < deadline do task.wait(0.1) end
end)
