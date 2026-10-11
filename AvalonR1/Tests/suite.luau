local Mat4 = MODULES.Mat4
local Mesh = MODULES.Mesh
local Camera = MODULES.Camera
local Texture = MODULES.Texture
local Renderer = MODULES.Renderer

local failures = 0
local function check(name, cond, extra)
	if cond then
		print(string.format("  ok    %s", name))
	else
		failures += 1
		print(string.format("  FAIL  %s  (%s)", name, tostring(extra)))
	end
end

local function isReddish(w)
	return w % 256 > 100 and (w // 256) % 256 < 60 and (w // 65536) % 256 < 60
end

print("Mat4")
local m = Mat4.perspective(math.rad(90), 1, 1, 100)
local _, _, _, w = Mat4.transformPoint(m, 0, 0, -5)
check("perspective: w == view distance", math.abs(w - 5) < 1e-6, w)
local vp = Mat4.mul(Mat4.perspective(math.rad(90), 1, 1, 100), Mat4.lookAt(Vector3.new(0, 0, 6), Vector3.new(0, 0, 0), Vector3.new(0, 1, 0)))
local _, _, _, wv = Mat4.transformPoint(vp, 0, 0, 0)
check("view+proj: origin is 6 away", math.abs(wv - 6) < 1e-5, wv)

print("Mesh generators")
local meshes = {
	{ "cube", Mesh.cube(Vector3.new(2, 2, 2)) },
	{ "plane", Mesh.plane(10, 4) },
	{ "sphere", Mesh.sphere(1.5, 12, 16) },
	{ "torus", Mesh.torus(1.6, 0.5, 20, 10) },
}
for _, spec in meshes do
	local name, mesh = spec[1], spec[2]
	check(name .. ": indices are complete", #mesh.indices == mesh.triangleCount * 3, #mesh.indices)
	check(name .. ": vertex arrays aligned", #mesh.positions == #mesh.normals and #mesh.normals == #mesh.uvs,
		#mesh.positions .. "/" .. #mesh.normals .. "/" .. #mesh.uvs)
	local bad = 0
	for t = 1, mesh.triangleCount do
		local i0, i1, i2 = mesh.indices[t * 3 - 2], mesh.indices[t * 3 - 1], mesh.indices[t * 3]
		if i0 == nil or i1 == nil or i2 == nil
			or mesh.positions[i0] == nil or mesh.positions[i1] == nil or mesh.positions[i2] == nil
			or mesh.normals[i0] == nil or mesh.uvs[i0] == nil then
			bad += 1
		end
	end
	check(name .. ": every triangle resolves", bad == 0, bad)
end

print("Renderer / Rasterizer")
local r = Renderer.new(Inst.new("Frame"), { width = 64, height = 64, adaptive = false })
r:setCamera(Camera.new({ position = Vector3.new(0, 0, 6), target = Vector3.new(0, 0, 0), fov = math.rad(60), near = 0.1, far = 100 }))
local centre = 32 * 64 + 32

r:beginFrame()
r:drawMesh(Mesh.cube(Vector3.new(2, 2, 2)), { shading = "flat", color = Color3.fromRGB(255, 0, 0) })
r:present()
local word = buffer.readu32(r.fb.color, centre * 4)
check("cube centre is lit red", isReddish(word), word)
local lit = 0
for i = 0, 64 * 64 - 1 do
	if buffer.readu32(r.fb.color, i * 4) % 256 > 100 then lit += 1 end
end
check("cube covers a sane area", lit > 300 and lit < 1500, lit)
check("background preserved", buffer.readu32(r.fb.color, 0) % 256 < 100)

r:beginFrame()
r:drawMesh(Mesh.cube(Vector3.new(4, 4, 4)), { shading = "flat", color = Color3.fromRGB(0, 0, 255), transform = Mat4.translation(Vector3.new(0, 0, -3)) })
r:drawMesh(Mesh.cube(Vector3.new(2, 2, 2)), { shading = "flat", color = Color3.fromRGB(255, 0, 0) })
r:present()
local dw = buffer.readu32(r.fb.color, centre * 4)
check("depth test: nearer (red) wins", isReddish(dw), dw)

r:beginFrame()
r:drawMesh(Mesh.cube(Vector3.new(2, 2, 2)), { shading = "flat", color = Color3.fromRGB(0, 255, 0), transform = Mat4.translation(Vector3.new(0, 0, 20)) })
r:present()
check("geometry behind camera culled", buffer.readu32(r.fb.color, centre * 4) % 256 < 100)

r:beginFrame()
r:drawMesh(Mesh.plane(400, 1), { shading = "flat", color = Color3.fromRGB(255, 255, 0), transform = Mat4.translation(Vector3.new(0, -2, 0)) })
r:present()
check("huge near-plane-straddling plane draws", true)

r:beginFrame()
r:drawMesh(meshes[3][2], { shading = "gouraud", color = Color3.fromRGB(90, 200, 255) })
r:present()
local sw = buffer.readu32(r.fb.color, centre * 4)
check("sphere renders and is visible", (sw // 65536) % 256 > 100, sw)

r:beginFrame()
r:drawMesh(meshes[4][2], {
	shading = "textured",
	texture = Texture.checker(8, 8, 4, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)),
	color = Color3.new(1, 1, 1),
})
r:present()
local tw = buffer.readu32(r.fb.color, centre * 4)
check("torus renders textured", (tw % 256 > 60) or ((tw // 256) % 256 > 60), tw)

print("Texture")
local t = Texture.checker(8, 8, 4, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
check("checker (0.1,0.1) is red", t:sample(0.1, 0.1) % 256 == 255, t:sample(0.1, 0.1))
check("checker (0.1,0.9) is green", (t:sample(0.1, 0.9) // 256) % 256 == 255, t:sample(0.1, 0.9))
check("wrap repeats", t:sample(1.1, 0.1) == t:sample(0.1, 0.1))

print("")
print(failures == 0 and "ALL TESTS PASS" or (failures .. " TEST(S) FAILED"))
