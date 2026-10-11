local V3 = {}
V3.__index = function(self, k)
	if k == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
	if k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then return V3.new(0, 0, 0) end
		return V3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return rawget(V3, k)
end
function V3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__add = function(a, b) return V3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return V3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return V3.new(-a.X, -a.Y, -a.Z) end
function V3.Dot(self, o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end
function V3.Cross(self, o)
	return V3.new(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X)
end
Vector3 = V3

local V2 = {}
V2.__index = V2
function V2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end
V2.zero = V2.new(0, 0)
Vector2 = V2

local C3 = {}
C3.__index = C3
function C3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end
function C3.fromRGB(r, g, b) return C3.new(r / 255, g / 255, b / 255) end
Color3 = C3

UDim2 = { fromScale = function(x, y) return { x = x, y = y } end, fromOffset = function(x, y) return { x = x, y = y } end }
UDim = { new = function() return {} end }
Enum = {
	ResamplerMode = { Pixelated = "Pixelated" },
	Font = { Code = "Code" },
	TextXAlignment = { Left = "Left" },
	TextYAlignment = { Top = "Top" },
}
Content = { fromObject = function(o) return o end }

local Inst = {}
Inst.__index = Inst
function Inst.new(class) return setmetatable({ ClassName = class }, Inst) end
function Inst:Destroy() end
Instance = Inst

local fakeImage = {}
fakeImage.__index = fakeImage
function fakeImage:WritePixelsBuffer(pos, size, buf) self.last = buf; self.calls = (self.calls or 0) + 1 end
function fakeImage:Destroy() end

game = {
	GetService = function(_, _)
		return {
			CreateEditableImage = function(_, opts) return setmetatable({ Size = opts.Size }, fakeImage) end,
		}
	end,
}
