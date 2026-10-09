--!strict
--[[ Emulator/CPU/Arm7tdmi.luau

 ARM7TDMI interpreter: full ARM and THUMB instruction sets, banked registers,
 CPSR/SPSR handling, exception vectors and cycle accounting.

 Registers are stored 1-based (regs[1] = R0 .. regs[16] = R15) so array indices
 line up with register numbers when read by humans.

 Modes: 0x10 User, 0x11 FIQ, 0x12 IRQ, 0x13 Supervisor, 0x17 Abort,
        0x1B Undefined, 0x1F System.
 ]]

local MODE_USER = 0x10
local MODE_FIQ = 0x11
local MODE_IRQ = 0x12
local MODE_SVC = 0x13
local MODE_ABT = 0x17
local MODE_UND = 0x1B
local MODE_SYS = 0x1F

local CPU = {}
CPU.__index = CPU

CPU.MODE_USER = MODE_USER
CPU.MODE_FIQ = MODE_FIQ
CPU.MODE_IRQ = MODE_IRQ
CPU.MODE_SVC = MODE_SVC
CPU.MODE_ABT = MODE_ABT
CPU.MODE_UND = MODE_UND
CPU.MODE_SYS = MODE_SYS

local function bankKey(m: number): number
	return (m == MODE_SYS) and MODE_USER or m
end

function CPU.new(bus: any)
	local cpu = {
		bus = bus,
		regs = table.create(16, 0),
		mode = MODE_SVC,
		thumb = false,
		n = false, z = false, c = false, v = false,
		irqDisable = true, fiqDisable = true,
		spsr = 0,
		bank = {
			[MODE_USER] = { r13 = 0, r14 = 0 },
			[MODE_FIQ] = { r13 = 0, r14 = 0, r8 = 0, r9 = 0, r10 = 0, r11 = 0, r12 = 0 },
			[MODE_IRQ] = { r13 = 0, r14 = 0 },
			[MODE_SVC] = { r13 = 0, r14 = 0 },
			[MODE_ABT] = { r13 = 0, r14 = 0 },
			[MODE_UND] = { r13 = 0, r14 = 0 },
		},
		cycles = 0,
		halted = false,
		-- diagnostics counters
		instructions = 0,
		lastPc = 0,
	}
	return setmetatable(cpu, CPU) :: any
end

--- Reset into Supervisor mode at the ROM entry point (HLE-friendly boot).
function CPU:reset(entryPoint: number?)
	for i = 1, 16 do self.regs[i] = 0 end
	self.mode = MODE_SVC
	self.thumb = false
	self.n = false; self.z = false; self.c = false; self.v = false
	self.irqDisable = true; self.fiqDisable = true
	self.spsr = 0
	self.bank[MODE_SVC].r13 = 0x03007FE0
	self.bank[MODE_SVC].r14 = 0
	self.bank[MODE_IRQ].r13 = 0x03007FA0
	self.bank[MODE_USER].r13 = 0x03007F00
	self.bank[MODE_USER].r14 = 0
	self.bank[MODE_FIQ].r13 = 0x03007F00
	self.bank[MODE_FIQ].r14 = 0
	self.bank[MODE_ABT].r13 = 0x03007F00
	self.bank[MODE_ABT].r14 = 0
	self.bank[MODE_UND].r13 = 0x03007F00
	self.bank[MODE_UND].r14 = 0
	self.regs[14] = 0x03007FE0 -- SP_svc
	self.regs[16] = (entryPoint or 0x08000000) % 0x10000000
	self.cycles = 0
	self.halted = false
end

-- Mode / banking ------------------------------------------------------------

function CPU:_setMode(newMode: number)
	local old = self.mode
	if old == newMode then return end
	local ok = bankKey(old)
	local ob = self.bank[ok]
	ob.r13 = self.regs[14]
	ob.r14 = self.regs[15]
	if ok == MODE_FIQ then
		ob.r8, ob.r9, ob.r10, ob.r11, ob.r12 = self.regs[9], self.regs[10], self.regs[11], self.regs[12], self.regs[13]
	end
	if old ~= MODE_USER and old ~= MODE_SYS then ob.spsr = self.spsr end

	self.mode = newMode
	local nk = bankKey(newMode)
	local nb = self.bank[nk]
	self.regs[14] = nb.r13 or 0
	self.regs[15] = nb.r14 or 0
	if nk == MODE_FIQ then
		self.regs[9], self.regs[10], self.regs[11], self.regs[12], self.regs[13] =
			nb.r8 or 0, nb.r9 or 0, nb.r10 or 0, nb.r11 or 0, nb.r12 or 0
	end
	if newMode ~= MODE_USER and newMode ~= MODE_SYS then self.spsr = nb.spsr or 0 end
end

function CPU:setCPSR(value: number)
	self.n = bit32.band(value, 0x80000000) ~= 0
	self.z = bit32.band(value, 0x40000000) ~= 0
	self.c = bit32.band(value, 0x20000000) ~= 0
	self.v = bit32.band(value, 0x10000000) ~= 0
	self.irqDisable = bit32.band(value, 0x80) ~= 0
	self.fiqDisable = bit32.band(value, 0x40) ~= 0
	self.thumb = bit32.band(value, 0x20) ~= 0
	local mode = bit32.band(value, 0x1F)
	if mode ~= self.mode then self:_setMode(mode) end
end

function CPU:cpsr(): number
	local v = self.mode
	if self.thumb then v = bit32.bor(v, 0x20) end
	if self.fiqDisable then v = bit32.bor(v, 0x40) end
	if self.irqDisable then v = bit32.bor(v, 0x80) end
	if self.n then v = bit32.bor(v, 0x80000000) end
	if self.z then v = bit32.bor(v, 0x40000000) end
	if self.c then v = bit32.bor(v, 0x20000000) end
	if self.v then v = bit32.bor(v, 0x10000000) end
	return v
end

-- Flags ---------------------------------------------------------------------

local function setNZ(cpu, value: number)
	local v = bit32.band(value, 0xFFFFFFFF)
	cpu.z = (v == 0)
	cpu.n = bit32.band(v, 0x80000000) ~= 0
end

local function addWithCarry(cpu, a: number, b: number, carryIn: number): number
	local r = a + b + carryIn
	local res = r % 0x100000000
	cpu.c = r > 0xFFFFFFFF
	local sa = bit32.band(a, 0x80000000) ~= 0
	local sb = bit32.band(b, 0x80000000) ~= 0
	local sr = bit32.band(res, 0x80000000) ~= 0
	cpu.v = (sa == sb) and (sa ~= sr)
	setNZ(cpu, res)
	return res
end

local function subWithCarry(cpu, a: number, b: number, carryIn: number): number
	local r = a - b - (1 - carryIn)
	local res = r % 0x100000000
	cpu.c = r >= 0
	local sa = bit32.band(a, 0x80000000) ~= 0
	local sb = bit32.band(b, 0x80000000) ~= 0
	local sr = bit32.band(res, 0x80000000) ~= 0
	cpu.v = (sa ~= sb) and (sa ~= sr)
	setNZ(cpu, res)
	return res
end

--- Evaluate the ARM condition code.
function CPU:condition(cond: number): boolean
	if cond == 0xE then return true end
	if cond == 0xF then return true end
	local n, z, c, v = self.n, self.z, self.c, self.v
	if cond == 0x0 then return z
	elseif cond == 0x1 then return not z
	elseif cond == 0x2 then return c
	elseif cond == 0x3 then return not c
	elseif cond == 0x4 then return n
	elseif cond == 0x5 then return not n
	elseif cond == 0x6 then return v
	elseif cond == 0x7 then return not v
	elseif cond == 0x8 then return c and not z
	elseif cond == 0x9 then return (not c) or z
	elseif cond == 0xA then return n == v
	elseif cond == 0xB then return n ~= v
	elseif cond == 0xC then return (not z) and (n == v)
	elseif cond == 0xD then return z or (n ~= v)
	end
	return false
end

-- Barrel shifter ------------------------------------------------------------

local function shiftOperand(cpu, value: number, type: number, amount: number, byRegister: boolean, regValue: number): number
	local carry = cpu.c
	if byRegister then
		if bit32.band(regValue, 0xFF) == 0 then return value end
		amount = bit32.band(regValue, 0xFF)
	end
	if type == 0 then -- LSL
		if amount == 0 then return value end
		if amount < 32 then
			carry = bit32.band(bit32.rshift(value, 32 - amount), 1) ~= 0
			return bit32.lshift(value, amount) % 0x100000000
		elseif amount == 32 then
			carry = bit32.band(value, 1) ~= 0
			return 0
		else
			carry = false
			return 0
		end
	elseif type == 1 then -- LSR
		if amount == 0 then
			if not byRegister then
				carry = bit32.band(value, 0x80000000) ~= 0
				return 0
			end
			return value
		end
		if amount < 32 then
			carry = bit32.band(bit32.rshift(value, amount - 1), 1) ~= 0
			return bit32.rshift(value, amount)
		elseif amount == 32 then
			carry = bit32.band(value, 0x80000000) ~= 0
			return 0
		else
			carry = false
			return 0
		end
	elseif type == 2 then -- ASR
		if amount == 0 or amount >= 32 then
			local sign = bit32.band(value, 0x80000000) ~= 0
			carry = sign
			return sign and 0xFFFFFFFF or 0
		end
		carry = bit32.band(bit32.rshift(value, amount - 1), 1) ~= 0
		return bit32.arshift(value, amount) % 0x100000000
	else -- ROR
		if amount == 0 then return value end
		amount %= 32
		if amount == 0 then
			carry = bit32.band(value, 0x80000000) ~= 0
			return value
		end
		local r = bit32.rrotate(value, amount)
		carry = bit32.band(r, 0x80000000) ~= 0
		return r
	end
end

CPU._shiftOperand = shiftOperand
CPU._addWithCarry = addWithCarry
CPU._subWithCarry = subWithCarry
CPU._setNZ = setNZ

-- Memory access helpers -----------------------------------------------------

function CPU:readWord(addr: number): number
	return self.bus:read32(addr % 0x10000000)
end

function CPU:writeWord(addr: number, value: number)
	self.bus:write32(addr % 0x10000000, value)
end

function CPU:readHalf(addr: number): number
	return self.bus:read16(addr % 0x10000000)
end

function CPU:writeHalf(addr: number, value: number)
	self.bus:write16(addr % 0x10000000, value)
end

function CPU:readByte(addr: number): number
	return self.bus:read8(addr % 0x10000000)
end

function CPU:writeByte(addr: number, value: number)
	self.bus:write8(addr % 0x10000000, value)
end

--- Read a register; R15 reads as PC + pipeline offset.
function CPU:reg(i: number): number
	if i == 16 then
		if self.thumb then return self.regs[16] + 2 end
		return self.regs[16] + 4
	end
	return self.regs[i]
end

--- Write a register. Writing R15 is a branch.
function CPU:setReg(i: number, value: number)
	if i == 16 then
		self:branch(value)
	else
		self.regs[i] = value % 0x100000000
	end
end

--- Branch, optionally honouring the THUMB state bit (BX / PC writes).
function CPU:branch(target: number, fromThumbSwitch: boolean?)
	target = target % 0x100000000
	if fromThumbSwitch then
		self.thumb = bit32.band(target, 1) ~= 0
		target = bit32.band(target, 0xFFFFFFFE)
	end
	self.regs[16] = target % 0x10000000
end

-- Exceptions -----------------------------------------------------------------

function CPU:exception(vector: number, newMode: number, returnAddr: number)
	local cpsr = self:cpsr()
	self:_setMode(newMode)
	self.spsr = cpsr
	self.regs[15] = returnAddr
	self.irqDisable = true
	if newMode == MODE_FIQ then self.fiqDisable = true end
	self.thumb = false
	self.regs[16] = vector
end

function CPU:swi(comment: number): boolean
	if self.bus.hleBios then
		return self.bus.hleBios:call(comment, self)
	end
	self:exception(0x08, MODE_SVC, self.regs[16] - 4)
	return false
end

function CPU:undefined()
	self:exception(0x04, MODE_UND, self.regs[16] - 4)
end

function CPU:checkIRQ(): boolean
	if self.irqDisable then return false end
	if not self.bus.interrupts then return false end
	if self.bus.interrupts:pending() then
		self:exception(0x18, MODE_IRQ, self.regs[16] + 4)
		return true
	end
	return false
end

-- ARM decode -----------------------------------------------------------------

local function ror(value: number, amount: number): number
	amount %= 32
	if amount == 0 then return value end
	return bit32.rrotate(value, amount)
end

function CPU:executeARM(op: number): number
	local cond = op // 0x10000000
	if cond == 0xF then
		if (op // 0x1000000) % 16 == 0xF then
			self:swi(op % 0x1000000)
			return 3
		end
		self:undefined()
		return 3
	end
	if not self:condition(cond) then return 1 end

		local op1 = (op // 0x2000000) % 8
	local nib = (op // 16) % 16
	local kind = (op // 0x1000000) % 16

	-- Multiply / long multiply: bits 27-24 = 0000, bits 7-4 = 1001
	if op1 == 0 and nib == 9 and kind == 0 then
		local mtype = (op // 0x200000) % 8
		if mtype == 0 or mtype == 1 then
			local rd = (op // 16) % 16
			local rn = (op // 12) % 16
			local rs = (op // 8) % 16
			local rm = op % 16
			local result = (self:reg(rm) * self:reg(rs)) % 0x100000000
			if mtype == 1 then result = (result + self:reg(rn)) % 0x100000000 end
			self:setReg(rd, result)
			if bit32.band(op, 0x100000) ~= 0 then setNZ(self, result) end
			return 3
		elseif mtype >= 2 and mtype <= 5 then
			local rm = op % 16
			local rs = (op // 8) % 16
			local rdHi = (op // 16) % 16
			local rdLo = (op // 12) % 16
			local a, b = self:reg(rm), self:reg(rs)
			local signed = mtype >= 4
			local prod
			if signed then
				local sa = bit32.band(a, 0x80000000) ~= 0 and a - 0x100000000 or a
				local sb = bit32.band(b, 0x80000000) ~= 0 and b - 0x100000000 or b
				prod = sa * sb
			else
				prod = a * b
			end
			if mtype == 3 or mtype == 5 then prod += self:reg(rdHi) * 0x100000000 + self:reg(rdLo) end
			local lo = prod % 0x100000000
			local hi = math.floor(prod / 0x100000000) % 0x100000000
			self:setReg(rdLo, lo)
			self:setReg(rdHi, hi)
			if bit32.band(op, 0x100000) ~= 0 then
				setNZ(self, lo)
				self.n = bit32.band(hi, 0x80000000) ~= 0
			end
			return 4
		end
		self:undefined()
		return 3
	end

	-- Swap: bits 27-24 = 0001, bits 7-4 = 1001
	if op1 == 0 and nib == 9 and kind == 1 then
		local rm = op % 16
		local rd = (op // 12) % 16
		local rn = (op // 16) % 16
		local byte = bit32.band(op, 0x400000) ~= 0
		local addr = self:reg(rn)
		local value = byte and self:readByte(addr) or self:readWord(addr)
		local src = self:reg(rm)
		if byte then self:writeByte(addr, src % 0x100) else self:writeWord(addr, src) end
		self:setReg(rd, value)
		return 4
	end

	-- Halfword / signed byte / signed halfword: bits 27-24 = 0000, bits 7-4 = 1SH1
	if op1 == 0 and kind == 0 and (nib == 0xB or nib == 0xD or nib == 0xF) then
		local rd = (op // 12) % 16
		local rn = (op // 16) % 16
		local immediate = bit32.band(op, 0x400000) ~= 0
		local offset
		if immediate then
			offset = bit32.bor(bit32.band(op, 0xF), bit32.band(op // 4, 0xF0))
		else
			offset = self:reg(op % 16)
		end
		local pre = bit32.band(op, 0x1000000) ~= 0
		local up = bit32.band(op, 0x800000) ~= 0
		local load = bit32.band(op, 0x100000) ~= 0
		local writeBack = bit32.band(op, 0x200000) ~= 0 or not pre
		local base = self:reg(rn)
		local wbAddr = up and (base + offset) or (base - offset)
		local effective = pre and wbAddr or base
		local value
		if load then
			if nib == 0xB then
				value = self:readHalf(effective)
			elseif nib == 0xD then
				value = self:readByte(effective)
				if bit32.band(value, 0x80) ~= 0 then value = value - 0x100 end
				value = value % 0x100000000
			else
				value = self:readHalf(effective)
				if bit32.band(value, 0x8000) ~= 0 then value = value - 0x10000 end
				value = value % 0x100000000
			end
		else
			value = self:reg(rd)
			if nib == 0xB then self:writeHalf(effective, value % 0x10000)
			else self:writeByte(effective, value % 0x100) end
		end
		if writeBack then self:setReg(rn, wbAddr) end
		if load then self:setReg(rd, value) end
		return 3
	end

	if op1 == 0 or op1 == 1 then
		local opcode = (op // 0x200000) % 16
		local s = (op // 0x100000) % 2
		local rn = (op // 0x10000) % 16
		local rd = (op // 0x1000) % 16
		local operand2
		local shifterCarry = self.c
		if op1 == 1 then
			local imm = op % 0x100
			local rot = ((op // 0x100) % 16) * 2
			operand2 = ror(imm, rot)
			if rot ~= 0 then shifterCarry = bit32.band(operand2, 0x80000000) ~= 0 end
		else
			local rm = op % 16
			local shiftType = (op // 0x20) % 4
			if bit32.band(op, 0x10) ~= 0 then
				local rs = (op // 0x100) % 16
				local amount = self:reg(rs) % 256
				if amount == 0 then
					operand2 = self:reg(rm)
				else
					operand2 = shiftOperand(self, self:reg(rm), shiftType, 0, true, amount)
					shifterCarry = self.c
				end
			else
				local amount = (op // 0x80) % 32
				local oldCarry = self.c
				operand2 = shiftOperand(self, self:reg(rm), shiftType, amount, false, 0)
				if amount ~= 0 or shiftType == 2 then shifterCarry = self.c else shifterCarry = oldCarry end
			end
		end

		local a = self:reg(rn)
		local result
		local writeBack = true
		local isSub = false
		local isAdd = false
		if opcode == 0 then result = bit32.band(a, operand2)
		elseif opcode == 1 then result = bit32.bxor(a, operand2)
		elseif opcode == 2 then result = subWithCarry(self, a, operand2, 1); isSub = true
		elseif opcode == 3 then result = subWithCarry(self, operand2, a, 1); isSub = true
		elseif opcode == 4 then result = addWithCarry(self, a, operand2, 0); isAdd = true
		elseif opcode == 5 then result = addWithCarry(self, a, operand2, self.c and 1 or 0); isAdd = true
		elseif opcode == 6 then result = subWithCarry(self, a, operand2, self.c and 1 or 0); isSub = true
		elseif opcode == 7 then result = subWithCarry(self, operand2, a, self.c and 1 or 0); isSub = true
		elseif opcode == 8 then result = bit32.band(a, operand2); writeBack = false
		elseif opcode == 9 then result = bit32.bxor(a, operand2); writeBack = false
		elseif opcode == 10 then result = subWithCarry(self, a, operand2, 1); writeBack = false; isSub = true
		elseif opcode == 11 then result = addWithCarry(self, a, operand2, 0); writeBack = false; isAdd = true
		elseif opcode == 12 then result = bit32.bor(a, operand2)
		elseif opcode == 13 then result = operand2
		elseif opcode == 14 then result = bit32.band(a, bit32.bnot(operand2))
		else result = bit32.bnot(operand2) end
		result = result % 0x100000000

		local isTest = opcode >= 8 and opcode <= 11
		if isTest or s == 1 then
			setNZ(self, result)
			if not (isSub or isAdd) then self.c = shifterCarry end
		end
		if writeBack then self:setReg(rd, result) end
		return 1
	end

	return self:executeARM2(op, op1)
end

function CPU:executeARM2(op: number, op1: number): number
	local kind = (op // 0x1000000) % 16

	-- PSR transfers: MRS / MSR (bits 27-24 = 0001, bits 7-4 = 0000)
	if op1 == 0 and kind == 1 and ((op // 16) % 16) ~= 9 then
		local useSPSR = bit32.band(op, 0x400000) ~= 0
		local rd = (op // 0x1000) % 16
		local subOp = (op // 0x100000) % 4
		if subOp == 0 then
			self:setReg(rd, useSPSR and self.spsr or self:cpsr())
		else
			local fieldMask = (op // 0x10000) % 16
			local value
			if bit32.band(op, 0x2000000) ~= 0 then
				value = ror(op % 0x100, ((op // 0x100) % 16) * 2)
			else
				value = self:reg(op % 16)
			end
			local mask = 0
			if bit32.band(fieldMask, 1) ~= 0 then mask = bit32.bor(mask, 0xF0000000) end
			if bit32.band(fieldMask, 2) ~= 0 then mask = bit32.bor(mask, 0x20) end
			if bit32.band(fieldMask, 4) ~= 0 then mask = bit32.bor(mask, 0xC0) end
			if bit32.band(fieldMask, 8) ~= 0 then mask = bit32.bor(mask, 0xFF) end
			if useSPSR then
				self.spsr = bit32.bor(bit32.band(self.spsr, bit32.bnot(mask)), bit32.band(value, mask))
			else
				local cur = self:cpsr()
				self:setCPSR(bit32.bor(bit32.band(cur, bit32.bnot(mask)), bit32.band(value, mask)))
			end
		end
		return 1
	end

	-- Single data transfer (immediate or register offset)
	if op1 == 2 or op1 == 3 then
		local load = bit32.band(op, 0x100000) ~= 0
		local byte = bit32.band(op, 0x400000) ~= 0
		local writeBack = bit32.band(op, 0x200000) ~= 0
		local pre = bit32.band(op, 0x1000000) ~= 0
		local up = bit32.band(op, 0x800000) ~= 0
		local rn = (op // 0x10000) % 16
		local rd = (op // 0x1000) % 16
		local offset
		if op1 == 2 then
			offset = op % 0x1000
		else
			offset = shiftOperand(self, self:reg(op % 16), (op // 0x20) % 4, (op // 0x80) % 32, false, 0)
		end
		local base = self:reg(rn)
		local addr = up and (base + offset) or (base - offset)
		local effective = pre and addr or base
		local value
		if load then
			if byte then
				value = self:readByte(effective)
			else
				local aligned = bit32.band(effective, 0xFFFFFFFC)
				value = self:readWord(aligned)
				local rot = (effective % 4) * 8
				if rot ~= 0 then value = bit32.rrotate(value, rot) end
			end
		else
			if byte then self:writeByte(effective, self:reg(rd) % 0x100)
			else self:writeWord(effective, self:reg(rd)) end
		end
		if (not pre) or writeBack then self:setReg(rn, addr) end
		if load then self:setReg(rd, value) end
		return 3
	end

	-- Block data transfer (LDM/STM)
	if op1 == 4 then
		local pre = bit32.band(op, 0x1000000) ~= 0
		local up = bit32.band(op, 0x800000) ~= 0
		local psr = bit32.band(op, 0x400000) ~= 0
		local writeBack = bit32.band(op, 0x200000) ~= 0
		local load = bit32.band(op, 0x100000) ~= 0
		local rn = (op // 0x10000) % 16
		local list = op % 0x10000
		local count = 0
		for i = 0, 15 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then count += 1 end
		end
		local base = self:reg(rn)
		local start, wb
		if up then
			start = pre and (base + 4) or base
			wb = base + 4 * count
		else
			start = pre and (base - 4 * count) or (base - 4 * count + 4)
			wb = base - 4 * count
		end
		local addr = start
		for i = 0, 15 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then
				if load then
					local v = self:readWord(addr)
					if i == 15 then
						if psr then self:setCPSR(self.spsr) end
						self:branch(v)
					else
						self.regs[i + 1] = v
					end
				else
					self:writeWord(addr, self.regs[i + 1])
				end
				addr += 4
			end
		end
		if writeBack then self:setReg(rn, wb) end
		return 3 + count
	end

	-- Branch / branch with link
	if op1 == 5 then
		local link = bit32.band(op, 0x1000000) ~= 0
		local offset = op % 0x1000000
		if bit32.band(offset, 0x800000) ~= 0 then offset -= 0x1000000 end
		local next = self.regs[16]
		if link then self.regs[15] = next end
		self.regs[16] = (next + 4 + offset * 4) % 0x10000000
		return 3
	end

	self:undefined()
	return 3
end

-- THUMB decode ---------------------------------------------------------------

function CPU:executeTHUMB(op: number): number
	local top = op // 0x1000

	-- Formats 1 & 2 -----------------------------------------------------------
	if top <= 0x1 then
		if (op // 0x800) % 4 == 3 then
			-- Format 2: add/subtract
			local opc = (op // 0x40) % 16
			local rs = (op // 8) % 8
			local rd = op % 8
			local operand
			if opc < 2 then operand = self.regs[rs + 1] else operand = (op // 0x40) % 8 end
			local a = self.regs[rs + 1]
			local result
			if opc == 0 or opc == 2 then result = addWithCarry(self, a, operand, 0)
			else result = subWithCarry(self, a, operand, 1) end
			self.regs[rd + 1] = result
			return 1
		end
		-- Format 1: LSL/LSR/ASR immediate
		local shiftType = (op // 0x800) % 4
		local amount = (op // 0x40) % 32
		local rs = (op // 8) % 8
		local rd = op % 8
		local result = shiftOperand(self, self.regs[rs + 1], shiftType, amount, false, 0)
		self.regs[rd + 1] = result
		setNZ(self, result)
		return 1
	end

	-- Format 3: move/compare/add/subtract immediate ---------------------------
	if top == 0x2 or top == 0x3 then
		local opc = (op // 0x800) % 4
		local rd = (op // 0x100) % 8
		local imm = op % 0x100
		local cur = self.regs[rd + 1]
		if opc == 0 then
			self.regs[rd + 1] = imm
			setNZ(self, imm)
		elseif opc == 1 then
			subWithCarry(self, cur, imm, 1)
		elseif opc == 2 then
			self.regs[rd + 1] = addWithCarry(self, cur, imm, 0)
		else
			self.regs[rd + 1] = subWithCarry(self, cur, imm, 1)
		end
		return 1
	end

	-- Format 4: ALU operations ------------------------------------------------
	if top == 0x4 and (op // 0x400) % 4 == 0 then
		local opc = (op // 0x40) % 16
		local rs = (op // 8) % 8
		local rd = op % 8
		local a = self.regs[rd + 1]
		local b = self.regs[rs + 1]
		local result
		local testOnly = false
		if opc == 0 then result = bit32.band(a, b)
		elseif opc == 1 then result = bit32.bxor(a, b)
		elseif opc == 2 then result = shiftOperand(self, a, 0, b % 256, true, b)
		elseif opc == 3 then result = shiftOperand(self, a, 1, b % 256, true, b)
		elseif opc == 4 then result = shiftOperand(self, a, 2, b % 256, true, b)
		elseif opc == 5 then result = addWithCarry(self, a, b, self.c and 1 or 0)
		elseif opc == 6 then result = subWithCarry(self, a, b, self.c and 1 or 0)
		elseif opc == 7 then result = shiftOperand(self, a, 3, b % 256, true, b)
		elseif opc == 8 then result = bit32.band(a, b); testOnly = true
		elseif opc == 9 then result = subWithCarry(self, 0, b, 1)
		elseif opc == 10 then result = subWithCarry(self, a, b, 1); testOnly = true
		elseif opc == 11 then result = addWithCarry(self, a, b, 0); testOnly = true
		elseif opc == 12 then result = bit32.bor(a, b)
		elseif opc == 13 then result = (a * b) % 0x100000000
		elseif opc == 14 then result = bit32.band(a, bit32.bnot(b))
		else result = bit32.bnot(b) end
		result = result % 0x100000000
		if testOnly then
			setNZ(self, result)
			if opc == 8 then self.c = self.c end
		else
			self.regs[rd + 1] = result
			if opc == 2 or opc == 3 or opc == 4 or opc == 7 then setNZ(self, result) end
		end
		return 1
	end

	-- Format 5: hi-register operations / BX -----------------------------------
	if top == 0x4 and (op // 0x400) % 4 == 1 then
		local opc = (op // 0x100) % 4
		local h1 = (op // 0x80) % 2
		local h2 = (op // 0x40) % 2
		local rs = (op // 8) % 8 + h2 * 8
		local rd = op % 8 + h1 * 8
		if opc == 3 then
			self:branch(self:reg(rs + 1), true)
			return 3
		end
		local a = self:reg(rd + 1)
		local b = self:reg(rs + 1)
		if opc == 0 then
			self:setReg(rd + 1, addWithCarry(self, a, b, 0))
		elseif opc == 1 then
			subWithCarry(self, a, b, 1)
		elseif opc == 2 then
			self:setReg(rd + 1, b)
		end
		return 1
	end

	-- Format 6: PC-relative load ----------------------------------------------
	if top == 0x4 and (op // 0x400) % 4 >= 2 then
		local rd = (op // 0x100) % 8
		local imm = (op % 0x100) * 4
		local pc = bit32.band(self.regs[16] + 2, 0xFFFFFFFC)
		self.regs[rd + 1] = self:readWord(pc + imm)
		return 3
	end

	-- Formats 7 & 8: load/store with register offset --------------------------
	if top >= 0x5 and top <= 0x5 then
		local opc = (op // 0x200) % 8
		local ro = (op // 0x40) % 8
		local rb = (op // 8) % 8
		local rd = op % 8
		local addr = self.regs[rb + 1] + self.regs[ro + 1]
		if opc == 0 then self:writeWord(addr, self.regs[rd + 1])
		elseif opc == 1 then self:writeHalf(addr, self.regs[rd + 1] % 0x10000)
		elseif opc == 2 then self:writeByte(addr, self.regs[rd + 1] % 0x100)
		elseif opc == 3 then
			local v = self:readByte(addr)
			if bit32.band(v, 0x80) ~= 0 then v -= 0x100 end
			self.regs[rd + 1] = v % 0x100000000
		elseif opc == 4 then self.regs[rd + 1] = self:readWord(addr)
		elseif opc == 5 then self.regs[rd + 1] = self:readHalf(addr)
		elseif opc == 6 then self.regs[rd + 1] = self:readByte(addr)
		else
			local v = self:readHalf(addr)
			if bit32.band(v, 0x8000) ~= 0 then v -= 0x10000 end
			self.regs[rd + 1] = v % 0x100000000
		end
		return 3
	end

	-- Format 9: immediate offset word/byte ------------------------------------
	if top >= 0x6 and top <= 0x7 then
		local byte = bit32.band(op, 0x1000) ~= 0
		local load = bit32.band(op, 0x800) ~= 0
		local offset = (op // 0x40) % 32
		local rb = (op // 8) % 8
		local rd = op % 8
		local addr = self.regs[rb + 1] + (byte and offset or offset * 4)
		if load then
			if byte then self.regs[rd + 1] = self:readByte(addr)
			else self.regs[rd + 1] = self:readWord(addr) end
		else
			if byte then self:writeByte(addr, self.regs[rd + 1] % 0x100)
			else self:writeWord(addr, self.regs[rd + 1]) end
		end
		return 3
	end

	-- Format 10: halfword immediate offset ------------------------------------
	if top == 0x8 then
		local load = bit32.band(op, 0x800) ~= 0
		local offset = ((op // 0x40) % 32) * 2
		local rb = (op // 8) % 8
		local rd = op % 8
		local addr = self.regs[rb + 1] + offset
		if load then self.regs[rd + 1] = self:readHalf(addr)
		else self:writeHalf(addr, self.regs[rd + 1] % 0x10000) end
		return 3
	end

	-- Format 11: SP-relative load/store ---------------------------------------
	if top == 0x9 then
		local load = bit32.band(op, 0x800) ~= 0
		local rd = (op // 0x100) % 8
		local imm = (op % 0x100) * 4
		local addr = self.regs[14] + imm
		if load then self.regs[rd + 1] = self:readWord(addr)
		else self:writeWord(addr, self.regs[rd + 1]) end
		return 3
	end

	-- Format 12: load address --------------------------------------------------
	if top == 0xA then
		local useSP = bit32.band(op, 0x800) ~= 0
		local rd = (op // 0x100) % 8
		local imm = (op % 0x100) * 4
		if useSP then
			self.regs[rd + 1] = (self.regs[14] + imm) % 0x100000000
		else
			local pc = bit32.band(self.regs[16] + 2, 0xFFFFFFFC)
			self.regs[rd + 1] = (pc + imm) % 0x100000000
		end
		return 1
	end

	-- Format 13: add offset to stack pointer -----------------------------------
	if (op // 0x100) == 0xB0 then
		local sub = bit32.band(op, 0x80) ~= 0
		local imm = (op % 0x80) * 4
		if sub then self.regs[14] = (self.regs[14] - imm) % 0x100000000
		else self.regs[14] = (self.regs[14] + imm) % 0x100000000 end
		return 1
	end

	-- Format 14: push/pop ------------------------------------------------------
	local hi = op // 0x100
	if hi == 0xB4 or hi == 0xB5 then
		local r = bit32.band(op, 0x100) ~= 0
		local list = op % 0x100
		local count = 0
		for i = 0, 7 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then count += 1 end
		end
		if r then count += 1 end
		local sp = self.regs[14] - 4 * count
		for i = 0, 7 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then
				self:writeWord(sp, self.regs[i + 1])
				sp += 4
			end
		end
		if r then self:writeWord(sp, self.regs[15]) end
		self.regs[14] = (self.regs[14] - 4 * count) % 0x100000000
		return 3
	elseif hi == 0xBC or hi == 0xBD then
		local r = bit32.band(op, 0x100) ~= 0
		local list = op % 0x100
		local sp = self.regs[14]
		for i = 0, 7 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then
				self.regs[i + 1] = self:readWord(sp)
				sp += 4
			end
		end
		if r then
			local v = self:readWord(sp)
			sp += 4
			self.regs[16] = bit32.band(v, 0xFFFFFFFE) % 0x10000000
		end
		self.regs[14] = sp % 0x100000000
		return 3
	end

	-- Format 15: multiple load/store -------------------------------------------
	if top == 0xC then
		local load = bit32.band(op, 0x800) ~= 0
		local rb = (op // 0x100) % 8
		local list = op % 0x100
		local addr = self.regs[rb + 1]
		local count = 0
		for i = 0, 7 do
			if bit32.band(list, bit32.lshift(1, i)) ~= 0 then
				if load then self.regs[i + 1] = self:readWord(addr)
				else self:writeWord(addr, self.regs[i + 1]) end
				addr += 4
				count += 1
			end
		end
		if count > 0 then self.regs[rb + 1] = addr % 0x100000000 end
		return 3 + count
	end

	-- Format 16: conditional branch / SWI --------------------------------------
	if top == 0xD then
		local cond = (op // 0x100) % 16
		if cond == 0xF then
			self:swi(op % 0x100)
			return 3
		end
		if cond == 0xE then return 1 end
		if self:condition(cond) then
			local off = op % 0x100
			if bit32.band(off, 0x80) ~= 0 then off -= 0x100 end
			self.regs[16] = (self.regs[16] + 2 + off * 2) % 0x10000000
			return 3
		end
		return 1
	end

	-- Format 17: unconditional branch ------------------------------------------
	if op // 0x800 == 0x1C then
		local off = op % 0x800
		if bit32.band(off, 0x400) ~= 0 then off -= 0x800 end
		self.regs[16] = (self.regs[16] + 2 + off * 2) % 0x10000000
		return 3
	end

	-- Format 18: long branch with link -----------------------------------------
	local tag = op // 0x800
	if tag == 0x1E then
		local off = op % 0x800
		if bit32.band(off, 0x400) ~= 0 then off -= 0x800 end
		self.regs[15] = (self.regs[16] + 2 + off * 0x1000) % 0x100000000
		return 1
	elseif tag == 0x1F then
		local off = op % 0x800
		local ret = (self.regs[16] + 1) % 0x100000000
		local target = self.regs[15] + off * 2
		self.regs[15] = ret
		self.regs[16] = target % 0x10000000
		return 3
	end

	self:undefined()
	return 1
end

-- Execution loop --------------------------------------------------------------

--- Fetch, decode and execute a single instruction. Returns cycles consumed.
function CPU:step(): number
	if self:checkIRQ() then return 3 end
	local pc = self.regs[16]
	if self.thumb then
		local op = self.bus:read16(pc)
		self.regs[16] = (pc + 2) % 0x10000000
		self.instructions += 1
		self.lastPc = pc
		return self:executeTHUMB(op)
	else
		local op = self.bus:read32(pc)
		self.regs[16] = (pc + 4) % 0x10000000
		self.instructions += 1
		self.lastPc = pc
		return self:executeARM(op)
	end
end

return CPU

return CPU
