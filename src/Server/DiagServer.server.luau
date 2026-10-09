--!strict
--[[ Server/DiagServer.server.luau

 Server half of the diagnostics persistence. It owns the DataStore so findings
 survive rejoins ("check what it caught without running anything"), and exposes
 them to clients through a single RemoteFunction.

 Security note: this file is written the way the catcher itself demands -
   * no client input is trusted (type + length + rate validated)
   * writes are rate limited per player
   * nothing is written on behalf of a client except its own findings
   * no loadstring / getfenv anywhere
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)

local STORE_KEY = "session"
local MAX_ENTRIES = Config.DIAG.maxEvents
local MAX_MESSAGE_LEN = 512

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DIAG.dataStoreName)
end)

local findings: { any } = {}
local function load()
	if not store then return end
	local ok, data = pcall(function() return store:GetAsync(STORE_KEY) end)
	if ok and type(data) == "table" then findings = data end
end

local function save()
	if not store then return end
	pcall(function() store:SetAsync(STORE_KEY, findings) end)
end

local function validFinding(f: any): boolean
	if type(f) ~= "table" then return false end
	if type(f.message) ~= "string" or #f.message > MAX_MESSAGE_LEN then return false end
	if type(f.symbol) ~= "string" or #f.symbol > MAX_MESSAGE_LEN then return false end
	local okCategory = f.category == "error" or f.category == "bug"
		or f.category == "vulnerability" or f.category == "unfinished"
	return okCategory
end

local function merge(list: { any })
	for _, f in list do
		if validFinding(f) then
			findings[#findings + 1] = f
		end
	end
	while #findings > MAX_ENTRIES do table.remove(findings, 1) end
end

load()

-- Remotes --------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "GBADiagRemotes"
remotes.Parent = ReplicatedStorage

local push = Instance.new("RemoteFunction")
push.Name = "PushFindings"
push.Parent = remotes

local get = Instance.new("RemoteFunction")
get.Name = "GetFindings"
get.Parent = remotes

-- Rate limiting: 1 push every 5s per player.
local lastPush: { [Player]: number } = {}

push.OnServerInvoke = function(player: Player, payload: any): boolean
	local now = os.clock()
	if lastPush[player] and now - lastPush[player] < 5 then
		return false
	end
	lastPush[player] = now
	if type(payload) ~= "table" then return false end
	if #payload > 100 then return false end
	merge(payload)
	save()
	return true
end

get.OnServerInvoke = function(_player: Player): { any }
	return findings
end

Players.PlayerRemoving:Connect(function(player)
	lastPush[player] = nil
end)

Logger.info(`DIAG server persistence online ({#findings} findings restored)`)
