-- State: live information about a slot (cooldown, charges/count, usable, in range).
-- Wraps the client API differences (classic-style globals vs C_Spell / C_Container tables).
ActionWheels = ActionWheels or {}
local AW = ActionWheels

AW.GCD = 1.5 -- cooldowns this short are the global cooldown; not drawn

-- In combat the client hands addons "secret" values (cooldown times and the like). They can be
-- passed to widgets but never compared, branched on or used in arithmetic, or the addon errors.
-- Everything below checks secret() before touching a value, and try() keeps one bad API call from
-- breaking the rest of a slot's state.
local function secret(v)
	return issecretvalue ~= nil and issecretvalue(v) and true or false
end

local function try(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end

local function range(r)
	if secret(r) then return nil end
	if r == 1 or r == true then return true end
	if r == 0 or r == false then return false end
	return nil
end

local function spellCooldown(name)
	if C_Spell and C_Spell.GetSpellCooldown then
		local c = C_Spell.GetSpellCooldown(name)
		if type(c) == "table" then return c.startTime, c.duration, c.isOnGCD end
		return nil
	end
	if GetSpellCooldown then
		local s, d = GetSpellCooldown(name)
		return s, d
	end
end

-- returns current, max (nil when the spell has no charges)
local function spellCharges(name)
	if C_Spell and C_Spell.GetSpellCharges then
		local c = C_Spell.GetSpellCharges(name)
		if type(c) == "table" then return c.currentCharges, c.maxCharges end
		return nil
	end
	if GetSpellCharges then
		local cur, max = GetSpellCharges(name)
		return cur, max
	end
end

local function spellUsable(name)
	if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
	if IsUsableSpell then return IsUsableSpell(name) end
end

local function spellRange(name)
	if C_Spell and C_Spell.IsSpellInRange then return range(C_Spell.IsSpellInRange(name, "target")) end
	if IsSpellInRange then return range(IsSpellInRange(name, "target")) end
end

local function itemId(name)
	if GetItemInfoInstant then
		local id = GetItemInfoInstant(name)
		return id
	end
end

local function itemCooldown(id)
	if not id then return end
	if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
	if GetItemCooldown then return GetItemCooldown(id) end
end

local function itemRange(name)
	if C_Item and C_Item.IsItemInRange then return range(C_Item.IsItemInRange(name, "target")) end
	if IsItemInRange then return range(IsItemInRange(name, "target")) end
end

local function itemCount(name)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(name) end
	if GetItemCount then return GetItemCount(name) end
end

-- Is the player carrying a buff with this name? (Aspects, stances-as-auras, self buffs.)
local function hasBuff(name)
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		return C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL") ~= nil
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		return AuraUtil.FindAuraByName(name, "player", "HELPFUL") ~= nil
	end
	if UnitAura then
		for i = 1, 40 do
			local n = UnitAura("player", i, "HELPFUL")
			if not n then return false end
			if n == name then return true end
		end
	end
	return false
end
AW.HasBuff = hasBuff

-- Returns { cdStart, cdDur, cdSecret, count, usable, noMana, inRange, active }; any field may be nil.
-- cdSecret means the cooldown numbers are secret: they may only be handed to a Cooldown frame.
function AW.SlotState(slot)
	local st = {}
	if AW.IsEmpty(slot) then return st end
	local onGCD
	if slot.type == "spell" and slot.spell then
		local name = slot.spell
		st.cdStart, st.cdDur, onGCD = try(spellCooldown, name)
		local cur, max = try(spellCharges, name)
		if max ~= nil and cur ~= nil and not secret(max) and not secret(cur) and max > 1 then
			st.count = cur
			if cur > 0 then st.cdStart, st.cdDur = nil, nil end -- still castable: no swirl
		end
		local usable, noMana = try(spellUsable, name)
		if not secret(usable) and not secret(noMana) then
			st.usable, st.noMana = usable and true or false, noMana and true or false
		end
		st.inRange = try(spellRange, name)
		st.active = try(hasBuff, name) -- e.g. the Aspect you are in
	elseif slot.type == "item" and slot.item then
		local name = slot.item
		st.cdStart, st.cdDur = try(function() return itemCooldown(itemId(name)) end)
		local n = try(itemCount, name)
		if n ~= nil and not secret(n) then st.count = n end
		local usable, noMana = true, false
		if IsUsableItem then usable, noMana = try(IsUsableItem, name) end
		if not secret(usable) and not secret(noMana) then
			if st.count and st.count <= 0 then usable = false end
			st.usable, st.noMana = usable and true or false, noMana and true or false
		end
		st.inRange = try(itemRange, name)
	end
	-- cooldown: secret numbers are passed through untouched; plain ones drop the global cooldown
	if st.cdDur ~= nil or st.cdStart ~= nil then
		if secret(st.cdDur) or secret(st.cdStart) then
			st.cdSecret = true
			if onGCD ~= nil and not secret(onGCD) and onGCD then st.cdStart, st.cdDur, st.cdSecret = nil, nil, nil end
		elseif st.cdDur and st.cdDur <= AW.GCD then
			st.cdStart, st.cdDur = nil, nil
		end
	end
	return st
end

-- Colour for the icon: { r, g, b, desaturate }
function AW.StateTint(st)
	if st.usable == false then
		if st.noMana then return 0.5, 0.5, 1, false end
		return 0.4, 0.4, 0.4, true
	end
	if st.inRange == false then return 1, 0.3, 0.3, false end
	return 1, 1, 1, false
end
