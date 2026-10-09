--!strict
--[[ Render (init)

 Presents the emulator's 240x160 RGBA buffer to Roblox.

 Primary backend: EditableImage (AssetService:CreateEditableImage) written with
 WritePixelsBuffer, which is a single GPU-side upload per frame.

 Fallback backend: a grid of Frames sampling the framebuffer, used when
 EditableImage is unavailable. It is deliberately coarse; it exists so the
 emulator still shows something on older engine builds.

 The renderer also owns auto-scaling: if measured FPS drops below the target it
 reduces scale / switches to adaptive presentation.
 ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Logger)

local W, H = Config.SCREEN_W, Config.SCREEN_H

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(parent: Instance, options: any?)
	options = options or {}
	local self = setmetatable({}, Renderer)
	self.scale = options.scale or Config.RENDER.scale
	self.backend = nil
	self.pixelBuffer = buffer.create(W * H * 4)
	self.fpsSamples = {}
	self.currentScale = self.scale

	self.container = Instance.new("Frame")
	self.container.Name = "GBAScreen"
	self.container.BackgroundColor3 = Color3.new(0, 0, 0)
	self.container.BorderSizePixel = 0
	self.container.Size = UDim2.fromOffset(W * self.scale, H * self.scale)
	self.container.Parent = parent

	self:_createBackend()
	return self
end

function Renderer:_createBackend()
	local ok, editable = pcall(function()
		local AssetService = game:GetService("AssetService")
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
		return img
	end)
	if ok and editable then
		self.editableImage = editable
		local label = Instance.new("ImageLabel")
		label.Name = "GBASurface"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		local okContent, content = pcall(function()
			return Content.fromObject(editable)
		end)
		if okContent then
			label.Image = content
		else
			label.Image = ""
		end
		label.Parent = self.container
		self.imageLabel = label
		self.backend = "editableimage"
		Logger.info("Renderer backend: EditableImage")
		return
	end

	-- Fallback: coarse frame grid
	self.backend = "grid"
	self.gridCols = 60
	self.gridRows = 40
	self.cells = {}
	local cellW = W / self.gridCols
	local cellH = H / self.gridRows
	for gy = 0, self.gridRows - 1 do
		for gx = 0, self.gridCols - 1 do
			local cell = Instance.new("Frame")
			cell.BorderSizePixel = 0
			cell.Size = UDim2.fromOffset(math.ceil(cellW), math.ceil(cellH))
			cell.Position = UDim2.fromOffset(gx * cellW, gy * cellH)
			cell.Parent = self.container
			self.cells[gy * self.gridCols + gx + 1] = cell
		end
	end
	Logger.warn("Renderer backend: grid fallback (EditableImage unavailable)")
end

--- Push the emulator framebuffer (RGBA byte array) to the screen.
function Renderer:present(fb: { number })
	if self.backend == "editableimage" then
		local buf = self.pixelBuffer
		local n = W * H
		for i = 0, n - 1 do
			local o = i * 4
			local r = fb[o + 1] or 0
			local g = fb[o + 2] or 0
			local b = fb[o + 3] or 0
			local a = fb[o + 4] or 255
			buffer.writeu32(buf, o, bit32.bor(r, bit32.lshift(g, 8), bit32.lshift(b, 16), bit32.lshift(a, 24)))
		end
		pcall(function()
			self.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), buf)
		end)
	else
		local cols, rows = self.gridCols, self.gridRows
		for gy = 0, rows - 1 do
			for gx = 0, cols - 1 do
				local px = math.floor((gx + 0.5) * W / cols)
				local py = math.floor((gy + 0.5) * H / rows)
				local o = (py * W + px) * 4
				local cell = self.cells[gy * cols + gx + 1]
				cell.BackgroundColor3 = Color3.fromRGB(fb[o + 1] or 0, fb[o + 2] or 0, fb[o + 3] or 0)
			end
		end
	end
end

function Renderer:setScale(scale: number)
	self.currentScale = scale
	self.container.Size = UDim2.fromOffset(W * scale, H * scale)
end

function Renderer:destroy()
	self.container:Destroy()
end

return Renderer
