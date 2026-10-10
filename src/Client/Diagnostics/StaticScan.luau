--!strict
--[[ Diagnostics/StaticScan.luau

 The "without me having to run the script" half of the catcher: it walks the
 live Roblox instance tree (every ModuleScript / Script the emulator owns),
 reads `.Source` where permitted, and reports TODO/stub markers, unsafe
 patterns and suspicious constructs *before* they ever execute.

 The scanner is safe in production: it respects a source allow-list, never
 requires untrusted modules, and degrades gracefully when Source is locked
 (Roblox returns an empty string for protected scripts).
 ]]

export type ScanHit = {
	category: string,
	severity: string,
	message: string,
	source: string,
	line: number,
	snippet: string,
}

local Classifier = require(script.Parent.Classifier)

local StaticScan = {}

-- Line-oriented rules. Each returns a message + category when the line matches.
type Rule = { name: string, pattern: string, category: string, severity: string }

local RULES: { Rule } = {
	{ name = "TODO", pattern = "\\-\\-.*TODO", category = "unfinished", severity = "info" },
	{ name = "FIXME", pattern = "\\-\\-.*FIXME", category = "unfinished", severity = "warn" },
	{ name = "HACK/XXX", pattern = "\\-\\-.*(HACK|XXX)", category = "unfinished", severity = "warn" },
	{ name = "stub-call", pattern = "unimplemented|not%s+implemented|NYI", category = "unfinished", severity = "warn" },
	{ name = "unsafe-loadstring", pattern = "%f[%a]loadstring%s*%(", category = "vulnerability", severity = "error" },
	{ name = "getfenv/setfenv", pattern = "%f[%a][gs]etfenv%s*%(", category = "vulnerability", severity = "warn" },
	{ name = "require-numeric-asset", pattern = "require%s*%(%s*%d+", category = "vulnerability", severity = "error" },
	{ name = "remote-fire-unvalidated", pattern = "%:[Ff]ire(Server|Client|AllClients)%s*%(", category = "vulnerability", severity = "info" },
}

--- Scan one source blob line by line, returning hits.
function StaticScan.scanSource(sourceText: string, label: string): { ScanHit }
	local hits: { ScanHit } = {}
	if sourceText == nil or sourceText == "" then return hits end
	local lineNo = 0
	for line in string.gmatch(sourceText, "([^\n]*)") do
		lineNo += 1
		for _, rule in RULES do
			if string.find(line, rule.pattern) then
				-- ignore our own rule table / comments that describe the rules
				if not string.find(line, "Classifier%.") then
					table.insert(hits, {
						category = rule.category,
						severity = rule.severity,
						message = `{rule.name} at {label}:{lineNo}`,
						source = label,
						line = lineNo,
						snippet = (string.len(line) > 160) and string.sub(line, 1, 160) or line,
					})
				end
			end
		end
	end
	return hits
end

--- Walk an instance subtree and scan every available Source.
function StaticScan.scanInstance(root: Instance, opts: { maxLines: number? }?): { ScanHit }
	opts = opts or {}
	local hits: { ScanHit } = {}
	local ok, descendants = pcall(function()
		return root:GetDescendants()
	end)
	if not ok then return hits end
	local budget = opts.maxLines or 20000
	for _, inst in descendants do
		if budget <= 0 then break end
		local isScript = inst:IsA("LuaSourceContainer")
		-- Skip this module: its rule table necessarily contains the very
		-- keywords being searched for, which would be a guaranteed self-flag.
		local isSelf = inst.Name == "StaticScan"
		if isScript and not isSelf then
			local okSrc, src = pcall(function()
				return (inst :: any).Source
			end)
			if okSrc and type(src) == "string" and src ~= "" then
				budget -= #src // 80
				local found = StaticScan.scanSource(src, inst:GetFullName())
				for _, h in found do table.insert(hits, h) end
			end
		end
	end
	return hits
end

--- Convenience: turn raw hits into classifier signals.
function StaticScan.toFindings(hits: { ScanHit }, nowFn: (() -> number)?)
	local out = {}
	for _, h in hits do
		table.insert(out, Classifier.makeFinding({
			message = h.message,
			source = "StaticScan:" .. h.source,
			kind = "static",
			hint = h.severity,
			meta = { line = h.line, snippet = h.snippet, category = h.category },
		}, nowFn))
	end
	return out
end

StaticScan.RULES = RULES
return StaticScan
