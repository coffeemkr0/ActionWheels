-- State: live information about a slot (cooldown, charges/count, usable, in range).
-- Wraps the client API differences (classic-style globals vs C_Spell / C_Container tables).
ActionWheels = ActionWheels or {}
local AW = ActionWheels

AW.GCD = 1.5 -- cooldowns this short are the global cooldown; not drawn

local function range(r)
	if r == 1 or r == true then return true end
	if r == 0 or r == false then return false end
	return nil
end

local function spellCooldown(name)
	if C_Spell and C_Spell.GetSpellCooldown then
		local c = C_Spell.GetSpellCooldown(name)
		if type(c) == "table" then return c.startTime, c.duration end
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

-- Returns { cdStart, cdDur, count, usable, noMana, inRange, active }; any field may be nil.
function AW.SlotState(slot)
	local st = {}
	if AW.IsEmpty(slot) then return st end
	if slot.type == "spell" and slot.spell then
		local name = slot.spell
		st.cdStart, st.cdDur = spellCooldown(name)
		local cur, max = spellCharges(name)
		if max and max > 1 then
			st.count = cur
			if cur and cur > 0 then st.cdStart, st.cdDur = nil, nil end -- still castable: no swirl
		end
		local usable, noMana = spellUsable(name)
		st.usable, st.noMana = usable and true or false, noMana and true or false
		st.inRange = spellRange(name)
		st.active = hasBuff(name) -- e.g. the Aspect you are in
	elseif slot.type == "item" and slot.item then
		local name = slot.item
		st.cdStart, st.cdDur = itemCooldown(itemId(name))
		local n = itemCount(name)
		if n then st.count = n end
		local usable, noMana = true, false
		if IsUsableItem then usable, noMana = IsUsableItem(name) end
		if n and n <= 0 then usable = false end
		st.usable, st.noMana = usable and true or false, noMana and true or false
		st.inRange = itemRange(name)
	end
	if st.cdDur and st.cdDur <= AW.GCD then st.cdStart, st.cdDur = nil, nil end
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
