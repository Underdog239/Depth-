--!strict
--[[ Emulator/Save/SaveState.luau

 Snapshot / restore of the whole machine. Serialises the CPU register file,
 CPSR fields, banked registers, all memory arrays and the PPU/IO state into a
 plain table that can be cached in memory or pushed to a DataStore.
 ]]

local SaveState = {}

local function copyArray(src: { number }, dst: { number })
	for i = 1, #src do dst[i] = src[i] end
end

function SaveState.save(gba: any)
	local cpu = gba.cpu
	local bus = gba.bus
	local regs = table.create(16)
	for i = 1, 16 do regs[i] = cpu.regs[i] end
	local bank = {}
	for mode, data in cpu.bank do
		local copy = {}
		for k, v in data do copy[k] = v end
		bank[tostring(mode)] = copy
	end
	return {
		version = 1,
		cpu = {
			regs = regs,
			mode = cpu.mode,
			thumb = cpu.thumb,
			n = cpu.n, z = cpu.z, c = cpu.c, v = cpu.v,
			irqDisable = cpu.irqDisable,
			fiqDisable = cpu.fiqDisable,
			spsr = cpu.spsr,
			halted = cpu.halted,
			bank = bank,
		},
		mem = {
			ewram = table.clone(bus.ewram),
			iwram = table.clone(bus.iwram),
			pal = table.clone(bus.pal),
			vram = table.clone(bus.vram),
			oam = table.clone(bus.oam),
			io = table.clone(bus.io),
		},
		ppu = {
			dispcnt = gba.ppu.dispcnt,
			dispstat = gba.ppu.dispstat,
			line = gba.ppu.line,
			dot = gba.ppu.dot,
		},
		frames = gba.frames,
		save = gba:saveBytes(),
	}
end

function SaveState.load(gba: any, state: any): boolean
	if not state or state.version ~= 1 then return false end
	local cpu = gba.cpu
	local bus = gba.bus
	for i = 1, 16 do cpu.regs[i] = state.cpu.regs[i] end
	cpu.mode = state.cpu.mode
	cpu.thumb = state.cpu.thumb
	cpu.n, cpu.z, cpu.c, cpu.v = state.cpu.n, state.cpu.z, state.cpu.c, state.cpu.v
	cpu.irqDisable = state.cpu.irqDisable
	cpu.fiqDisable = state.cpu.fiqDisable
	cpu.spsr = state.cpu.spsr
	cpu.halted = state.cpu.halted
	for mode, data in state.cpu.bank do
		local target = cpu.bank[tonumber(mode)]
		if target then for k, v in data do target[k] = v end end
	end
	copyArray(state.mem.ewram, bus.ewram)
	copyArray(state.mem.iwram, bus.iwram)
	copyArray(state.mem.pal, bus.pal)
	copyArray(state.mem.vram, bus.vram)
	copyArray(state.mem.oam, bus.oam)
	copyArray(state.mem.io, bus.io)
	gba.ppu.dispcnt = state.ppu.dispcnt
	gba.ppu.dispstat = state.ppu.dispstat
	gba.ppu.line = state.ppu.line
	gba.ppu.dot = state.ppu.dot
	gba.frames = state.frames
	if state.save then gba:loadSaveBytes(state.save) end
	return true
end

return SaveState
