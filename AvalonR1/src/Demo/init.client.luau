--!strict
--[[
	Avalon R1 demo — a small animated scene that exercises the whole pipeline:
	textured floor, a spinning cube, a lit sphere, a rotating torus and a
	horizon gradient background. Drop this script in StarterPlayerScripts (or
	just press Play with the bundled Rojo project) and it renders a live 3D
	scene entirely inside a GUI, with no parts in the workspace.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Avalon = require(ReplicatedStorage:WaitForChild("Avalon"))
local Mat4 = Avalon.Mat4
local Mesh = Avalon.Mesh
local Texture = Avalon.Texture
local Camera = Avalon.Camera

-- GUI ------------------------------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "AvalonDemo"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = playerGui

local viewport = Instance.new("Frame")
viewport.Name = "Viewport"
viewport.BackgroundColor3 = Color3.new(0, 0, 0)
viewport.BorderSizePixel = 0
viewport.Size = UDim2.fromScale(1, 1)
viewport.Parent = screen

-- Scene ----------------------------------------------------------------------

local renderer = Avalon.new(viewport, {
	width = 480,
	height = 360,
	adaptive = true,
	targetFps = 60,
	background = Color3.fromRGB(10, 12, 20),
	light = Vector3.new(-0.35, -0.9, -0.45),
	ambient = 0.2,
})

local camera = Camera.new({
	position = Vector3.new(0, 3.2, 9),
	target = Vector3.new(0, 0.6, 0),
	fov = math.rad(68),
	near = 0.1,
	far = 200,
})
renderer:setCamera(camera)

local checker = Texture.checker(64, 64, 8, Vector3.new(0.95, 0.82, 0.32), Vector3.new(0.12, 0.12, 0.16))
local grid = Texture.checker(64, 64, 16, Vector3.new(0.18, 0.2, 0.26), Vector3.new(0.10, 0.11, 0.15))

local floorMesh = Mesh.plane(40, 10)
local cubeMesh = Mesh.cube(Vector3.new(2, 2, 2))
local sphereMesh = Mesh.sphere(1.3, 18, 28)
local torusMesh = Mesh.torus(1.7, 0.55, 28, 14)

-- HUD ------------------------------------------------------------------------

local hud = Instance.new("TextLabel")
hud.BackgroundTransparency = 1
hud.Font = Enum.Font.Code
hud.TextColor3 = Color3.fromRGB(230, 210, 140)
hud.TextXAlignment = Enum.TextXAlignment.Left
hud.TextYAlignment = Enum.TextYAlignment.Top
hud.TextSize = 16
hud.Position = UDim2.fromOffset(12, 10)
hud.Size = UDim2.fromOffset(360, 80)
hud.Text = ""
hud.Parent = viewport

-- Loop -----------------------------------------------------------------------

local elapsed = 0
local smoothedMs = 0

RunService.RenderStepped:Connect(function(dt)
	elapsed += dt

	-- Slow orbit so the depth buffer and lighting are both visible.
	local angle = elapsed * 0.35
	camera.position = Vector3.new(math.sin(angle) * 9, 3.2, math.cos(angle) * 9)
	camera.target = Vector3.new(0, 0.6, 0)

	renderer:beginFrame()

	renderer:drawMesh(floorMesh, {
		shading = "textured",
		texture = grid,
		color = Color3.fromRGB(150, 160, 180),
	})

	local spin = Mat4.mul(Mat4.rotationY(elapsed * 1.1), Mat4.rotationX(elapsed * 0.6))
	renderer:drawMesh(cubeMesh, {
		transform = Mat4.mul(Mat4.translation(Vector3.new(-3.4, 1, 0)), spin),
		shading = "textured",
		texture = checker,
	})

	renderer:drawMesh(sphereMesh, {
		transform = Mat4.translation(Vector3.new(0, 1.4, 0)),
		shading = "gouraud",
		color = Color3.fromRGB(90, 200, 255),
	})

	renderer:drawMesh(torusMesh, {
		transform = Mat4.mul(Mat4.translation(Vector3.new(3.4, 1.3, 0)), Mat4.rotationX(elapsed * 0.9)),
		shading = "textured",
		texture = checker,
		color = Color3.fromRGB(255, 140, 90),
	})

	renderer:present()

	local ms = renderer.stats.ms
	smoothedMs = smoothedMs == 0 and ms or (smoothedMs * 0.9 + ms * 0.1)
	hud.Text = string.format(
		"Avalon R1 %s\n%.1f ms  (%.0f fps)\n%d tris drawn / %d submitted\nres %dx%d  scale %.2f",
		Avalon.VERSION,
		smoothedMs,
		smoothedMs > 0 and 1000 / smoothedMs or 0,
		renderer.stats.drawn,
		renderer.stats.triangles,
		renderer.width,
		renderer.height,
		renderer.scale
	)
end)
