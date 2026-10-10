-- Small client launcher: place Depth-ROM.gba in your loader's workspace first.
-- Requires client readfile, HTTP and loadstring support. No ROM is uploaded.
local path = ... or "Depth-ROM.gba"
assert(type(path) == "string" and #path > 0, "Choose a ROM file path")
assert(type(readfile) == "function",
    "This loader has no readfile support. Use its file import feature or the embedded Depth-game.luau launcher.")
assert(type(loadstring) == "function", "This launcher needs client loadstring support")
local player = game:GetService("Players").LocalPlayer
assert(player, "Run this launcher in a Roblox player client")
local gui = player:WaitForChild("PlayerGui", 10)
assert(gui and not gui:FindFirstChild("LuauGBA"),
    "Depth is already open or PlayerGui is unavailable. Join a fresh session and run this launcher first.")
local ok, data = pcall(readfile, path)
assert(ok, "Could not read " .. path .. ". Put the .gba file in your loader's workspace folder with that exact name.")
assert(type(data) == "string" and #data >= 192 and #data <= 33554432,
    "ROM file must contain 192 bytes to 32 MiB of raw GBA data. Extract ZIP files first.")
local rom = buffer.fromstring(data)
data = nil
local fetched, source = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Underdog239/Depth-/coderabbit/explain-code-limit/230c69a5/installer/Depth-runtime.luau")
end)
assert(fetched, "Could not download Depth. Check your connection and client HTTP support.")
local start, failure = loadstring(source, "Depth-runtime")
assert(start, failure)
return start(rom)
