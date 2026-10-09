--!strict
--[[ Diagnostics/Classifier.luau

 Turns raw signals (runtime errors, static-analysis hits, invariant failures)
 into a normalized Finding with one of four categories the user asked for:

   * "error"         -- something actually blew up at runtime
   * "bug"           -- logically wrong / inconsistent behaviour
   * "vulnerability" -- security or exploit-adjacent weakness
   * "unfinished"    -- stubbed / TODO / placeholder code paths

 Classification is heuristic but deterministic and unit-tested in Tests/.
 ]]

export type Category = "error" | "bug" | "vulnerability" | "unfinished"
export type Severity = "info" | "warn" | "error" | "fatal"

export type Finding = {
	id: string,
	category: Category,
	severity: Severity,
	message: string,
	source: string,       -- originating subsystem
	symbol: string,       -- dedup key
	stack: string?,
	count: number,
	firstSeen: number,
	lastSeen: number,
	meta: { [string]: any }?,
}

local Classifier = {}

-- Patterns are checked in priority order; first match wins per category.

local VULN_PATTERNS = {
	{ "RemoteEvent without server validation", "%f[%a]RemoteEvent%f[%A]" },
	{ "FireServer/FireAllClients of untrusted data", "Fire(Server|AllClients)" },
	{ "loadstring / dynamic code execution", "%f[%a]loadstring%f[%A]" },
	{ "getfenv/setfenv usage", "[gs]etfenv" },
	{ "HttpService on the client", "HttpService" },
	{ "DataStore write from client", "DataStoreService" },
	{ "require of untrusted user asset", "require%(%s*%d+" },
	{ "unbounded loop over network data", "while%s+true" },
	{ "string as bytecode / obfuscation marker", "\\%d\\%d\\%d\\%d" },
}

local UNFINISHED_PATTERNS = {
	{ "TODO marker", "TODO" },
	{ "FIXME marker", "FIXME" },
	{ "XXX/HACK marker", "XXX|HACK" },
	{ "placeholder / stub", "placeholder|stub|not%s+implemented|NYI" },
	{ "unimplemented instruction", "unimplemented|unsupported%s+opcode|opcode%%?%%?" },
	{ "empty function body", "function[%w_%.]*%b()%s*return%s*end" },
	{ "error('not implemented')", "error%(%s*['\"]not" },
}

local BUG_PATTERNS = {
	{ "integer overflow without wrap", "0x100000000" },
	{ "index nil", "attempt to index nil" },
	{ "nil arithmetic", "attempt to perform arithmetic" },
	{ "out of bounds memory access", "out of bounds|oob access" },
	{ "infinite recursion", "stack overflow" },
	{ "type mismatch", "type mismatch" },
	{ "division by zero", "divide by zero|division by zero" },
}

local function containsAny(hay: string, patterns: { { string } }): string?
	for _, entry in patterns do
		if string.find(hay, entry[2]) then
			return entry[1]
		end
	end
	return nil
end

--- Derive severity from category + explicit hints.
local function severityFor(category: Category, hint: string?): Severity
	if hint == "fatal" or hint == "error" then return hint :: Severity end
	if category == "error" then return "error" end
	if category == "vulnerability" then return "warn" end
	if category == "bug" then return "warn" end
	return "info"
end

--- Stable dedup symbol: category + normalized message + source.
function Classifier.symbolFor(category: Category, message: string, source: string): string
	-- strip numbers/addresses so "read8(0x1FF)" and "read8(0x200)" dedup.
	local norm = message:gsub("%d+", "N"):gsub("[%x]+%.luau", "FILE")
	return `{category}|{source}|{norm}`
end

--- Classify a raw text signal into a category.
function Classifier.classify(message: string, source: string, kind: string?): Category
	local lower = string.lower(message)

	-- Explicit kind wins if the caller already knows.
	if kind == "runtime-error" or kind == "error" then
		-- but a security-flavoured error is still a vulnerability
		if containsAny(lower, VULN_PATTERNS) then return "vulnerability" end
		return "error"
	end

	local vuln = containsAny(lower, VULN_PATTERNS)
	if vuln then return "vulnerability" end

	local unf = containsAny(message, UNFINISHED_PATTERNS)
	if unf then return "unfinished" end

	local bug = containsAny(lower, BUG_PATTERNS)
	if bug then return "bug" end

	source = source or ""
	if string.find(lower, "attempt to") or string.find(lower, "stack overflow") then
		return "error"
	end
	return "bug"
end

--- Human-readable reason for a category decision (for dashboards/tooltips).
function Classifier.explain(message: string, source: string, kind: string?): string
	local lower = string.lower(message)
	local hit = containsAny(lower, VULN_PATTERNS)
	if hit then return `security signal: {hit}` end
	hit = containsAny(message, UNFINISHED_PATTERNS)
	if hit then return `incomplete code signal: {hit}` end
	hit = containsAny(lower, BUG_PATTERNS)
	if hit then return `correctness signal: {hit}` end
	if kind == "runtime-error" then return "uncaught runtime error" end
	return "default heuristic"
end

--- Build a Finding from a signal. Time is injectable for tests.
function Classifier.makeFinding(signal: {
	message: string,
	source: string?,
	kind: string?,
	stack: string?,
	meta: { [string]: any }?,
	hint: string?,
}, nowFn: (() -> number)?): Finding
	local nowFn2 = nowFn or os.clock
	local source = signal.source or "unknown"
	local message = signal.message or ""
	local category = Classifier.classify(message, source, signal.kind)
	local symbol = Classifier.symbolFor(category, message, source)
	return {
		id = symbol,
		category = category,
		severity = severityFor(category, signal.hint),
		message = message,
		source = source,
		symbol = symbol,
		stack = signal.stack,
		count = 1,
		firstSeen = nowFn2(),
		lastSeen = nowFn2(),
		meta = signal.meta,
	}
end

Classifier.VULN_PATTERNS = VULN_PATTERNS
Classifier.UNFINISHED_PATTERNS = UNFINISHED_PATTERNS
Classifier.BUG_PATTERNS = BUG_PATTERNS

return Classifier
