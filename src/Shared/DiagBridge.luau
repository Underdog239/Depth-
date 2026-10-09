--!strict
--[[ Shared/DiagBridge.luau

 Client-side bridge to the server diagnostics store. Lets the dashboard show
 findings that were caught in *previous* sessions, so the answer to "did it
 catch anything?" is available without re-running anything.

 Degrades gracefully: if the remotes are missing (solo play / no server half)
 every call returns an empty result instead of erroring.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiagBridge = {}

local function remote(name: string): any
	local folder = ReplicatedStorage:FindFirstChild("GBADiagRemotes")
	if not folder then return nil end
	return folder:FindFirstChild(name)
end

--- Pull persisted findings from the server (may be empty).
function DiagBridge.fetch(): { any }
	local rf = remote("GetFindings")
	if not rf then return {} end
	local ok, data = pcall(function() return rf:InvokeServer() end)
	if ok and type(data) == "table" then return data end
	return {}
end

--- Push local findings to the server for persistence.
function DiagBridge.push(list: { any }): boolean
	local rf = remote("PushFindings")
	if not rf then return false end
	local ok, result = pcall(function() return rf:InvokeServer(list) end)
	return ok and result == true
end

return DiagBridge
