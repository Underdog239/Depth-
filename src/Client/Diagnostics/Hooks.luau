--!strict
--[[ Diagnostics/Hooks.luau

 Installs the runtime surfaces that feed the catcher *without the user running
 anything*:

   * ScriptContext.Error        -- uncaught Lua errors visible to this client
   * LogService.MessageOut      -- warn()/print()/error() from any script
   * RunService.Heartbeat/Stepped -- for stall detection
   * a global pcatch wrapper    -- for our own guarded entry points

 Every hook is installed defensively (pcall + IsA checks) so a missing API in
 an older engine build never breaks boot.
 ]]

export type HookSink = (signal: {
	message: string,
	source: string?,
	kind: string?,
	stack: string?,
	meta: { [string]: any }?,
}) -> ()

local Hooks = {}
Hooks._connections = {} :: { RBXScriptConnection }
Hooks._installed = false

local function safeService(name: string): Instance?
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	return ok and svc or nil
end

--- Install all available hooks. Idempotent.
function Hooks.install(sink: HookSink)
	if Hooks._installed then return end
	Hooks._installed = true

	-- 1) Uncaught client errors
	local sc = safeService("ScriptContext")
	if sc then
		local ok, conn = pcall(function()
			return (sc :: any).Error:Connect(function(message: string, stack: string)
				sink({ message = message, stack = stack, source = "ScriptContext.Error", kind = "runtime-error" })
			end)
		end)
		if ok and conn then table.insert(Hooks._connections, conn) end
	end

	-- 2) LogService mirror catches warn()/error() text everywhere it is exposed
	local ls = safeService("LogService")
	if ls and (ls :: any).MessageOut then
		local okConn, conn = pcall(function()
			return (ls :: any).MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
				if message:sub(1, 5) == "[GBA/" then return end
				if messageType ~= Enum.MessageType.MessageError and messageType ~= Enum.MessageType.MessageWarning then return end
				local kind = "log"
				if messageType == Enum.MessageType.MessageError then kind = "runtime-error"
				elseif messageType == Enum.MessageType.MessageWarning then kind = "warn" end
				sink({ message = message, source = "LogService", kind = kind })
			end)
		end)
		if okConn and conn then table.insert(Hooks._connections, conn) end
	end

	-- 3) Heartbeat gives us a passive frame counter even when not rendering
	local rs = safeService("RunService")
	if rs then
		local okConn, conn = pcall(function()
			return (rs :: any).Heartbeat:Connect(function()
				Hooks._heartbeats += 1
			end)
		end)
		if okConn and conn then table.insert(Hooks._connections, conn) end
	end
end

Hooks._heartbeats = 0

--- Wrap a function so any error it raises is reported then re-raised safely.
function Hooks.guard(name: string, fn: (...any) -> ...any, sink: HookSink)
	return function(...)
		local packed = table.pack(pcall(fn, ...))
		if not packed[1] then
			sink({
				message = tostring(packed[2]),
				source = "guard:" .. name,
				kind = "runtime-error",
				stack = debug.traceback(nil, 2),
			})
		end
		return table.unpack(packed, 2, packed.n)
	end
end

function Hooks.heartbeats(): number
	return Hooks._heartbeats
end

function Hooks.uninstall()
	for _, conn in Hooks._connections do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(Hooks._connections)
	Hooks._installed = false
end

return Hooks
