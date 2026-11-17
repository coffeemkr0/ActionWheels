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

-- Is the player's buff `name` on? Best answer available, most reliable source first:
--   1. C_UnitAuras.GetPlayerAuraBySpellID(spellID): a targeted lookup the game exempts from the
--      secret-value rules for the player's own buffs. An aura means "on". An empty answer means
--      "off" out of combat, or in combat when C_Secrets.ShouldSpellAuraBeSecret(spellID) is false.
--   2. The older lookups (by name / by index), which work out of combat.
--   3. In combat, when the game won't say: what we last knew, kept current by UNIT_AURA removals
--      (auraInstanceID is never secret) and by your own successful casts (NoteCast).
AW.buffCache = {}      -- name -> true/false, last known
AW.auraInstance = {}   -- auraInstanceID -> name, for the buffs we track
AW.spellIdCache = {}
local EXCLUSIVE = "^Aspect of" -- Hunter Aspects replace one another

local function spellIdOf(name)
	local c = AW.spellIdCache[name]
	if c ~= nil then return c or nil end
	local id
	if C_Spell and C_Spell.GetSpellInfo then
		local i = C_Spell.GetSpellInfo(name)
		if type(i) == "table" then id = i.spellID end
	elseif GetSpellInfo then
		local _, _, _, _, _, _, sid = GetSpellInfo(name)
		id = sid
	end
	if secret(id) then return nil end
	AW.spellIdCache[name] = id or false
	return id
end

AW.buffLog = {} -- last few state changes with their source, for /aw buffs

local function remember(name, on, data, why)
	if AW.buffCache[name] ~= on then
		AW.buffLog[#AW.buffLog + 1] = string.format("%s -> %s (%s)", name, on and "on" or "off", why or "lookup")
		if #AW.buffLog > 20 then table.remove(AW.buffLog, 1) end
	end
	AW.buffCache[name] = on
	if on and string.find(name, EXCLUSIVE) then -- only one Aspect can be on
		for k in pairs(AW.buffCache) do
			if k ~= name and string.find(k, EXCLUSIVE) then AW.buffCache[k] = false end
		end
	end
	if on and data then
		local ok, iid = pcall(function() return data.auraInstanceID end)
		if ok and iid ~= nil and not secret(iid) then AW.auraInstance[iid] = name end
	end
end
AW.RememberBuff = remember

-- In combat the game hides buffs from addons, and "no answer" can look exactly like "buff is off".
-- So in combat a lookup may only CONFIRM a buff; turning one off needs real evidence (a removal
-- event for a buff we tracked, or you casting another Aspect). Out of combat the lookups are
-- complete and are believed either way.
function AW.IsBuffActive(name)
	local combat = AW.InCombat()
	local id = try(spellIdOf, name)
	if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if ok and not secret(data) then
			if data then remember(name, true, data, "targeted lookup") return true end
			if not combat then remember(name, false, nil, "targeted lookup, out of combat") return false end
		end
	end
	if combat then return AW.buffCache[name] and true or false end
	if try(hasBuff, name) then remember(name, true, nil, "aura scan") return true end
	remember(name, false, nil, "aura scan, out of combat")
	return false
end

-- UNIT_AURA for the player. Removals are tracked through the (never secret) auraInstanceID of
-- buffs we saw earlier; additions are matched by spell id when the game lets us read it.
function AW.OnAura(info)
	if type(info) ~= "table" then return end
	local ok = pcall(function()
		if info.removedAuraInstanceIDs then
			for _, iid in ipairs(info.removedAuraInstanceIDs) do
				local name = AW.auraInstance[iid]
				if name then
					remember(name, false, nil, "removal event")
					AW.auraInstance[iid] = nil
				end
			end
		end
		if info.addedAuras then
			for _, aura in ipairs(info.addedAuras) do
				local nm, sid = aura.name, aura.spellId
				if nm ~= nil and not secret(nm) and AW.buffCache[nm] ~= nil then remember(nm, true, aura, "added event") end
				if sid ~= nil and not secret(sid) then
					for tracked in pairs(AW.buffCache) do
						if spellIdOf(tracked) == sid then remember(tracked, true, aura, "added event") end
					end
				end
			end
		end
	end)
	return ok
end

-- Re-read every spell slot's buff (call out of combat / on aura changes).
function AW.UpdateBuffCache()
	if not (ActionWheelsDB and ActionWheelsDB.profile) then return end
	if AW.InCombat() then return end
	for _, w in pairs(AW.P().wheels) do
		for _, slot in pairs(w.items) do
			if slot.type == "spell" and slot.spell then AW.IsBuffActive(slot.spell) end
		end
	end
end

-- You clicked a spell slice: remember which spell, so a cast confirmation whose spell id the game
-- hides (it does in combat) can still be matched to it.
AW.pendingCast = nil
function AW.NoteClick(name)
	if name then AW.pendingCast = { name = name, t = GetTime() } end
end

-- UNIT_SPELLCAST_SUCCEEDED for the player. `spellId` may be secret; then the recent click decides.
function AW.OnCastSucceeded(spellId)
	local name
	if spellId ~= nil and not secret(spellId) and AW.SpellName then
		local ok, n = pcall(AW.SpellName, spellId)
		if ok then name = n end
	end
	local p = AW.pendingCast
	if p and GetTime() - p.t < 1.5 then
		-- an unreadable cast right after our click is that click's spell; a readable one must match
		if not name or name == p.name then name = p.name; AW.pendingCast = nil end
	end
	if name then AW.NoteCast(name) end
end

-- What each source says about every spell slot (for /aw buffs).
function AW.BuffReport()
	local out = {}
	local seen = {}
	for _, w in pairs(AW.P().wheels) do
		for _, slot in pairs(w.items) do
			if slot.type == "spell" and slot.spell and not seen[slot.spell] then
				seen[slot.spell] = true
				local id = try(spellIdOf, slot.spell)
				local tgt = "n/a"
				if id and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
					local ok, d = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
					tgt = (not ok and "error") or (secret(d) and "secret") or (d and "found" or "nil")
				end
				local sec = "n/a"
				if id and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
					local v = try(C_Secrets.ShouldSpellAuraBeSecret, id)
					sec = tostring(v)
				end
				out[#out + 1] = slot.spell .. ": id=" .. tostring(id) .. " targeted=" .. tgt ..
					" shouldBeSecret=" .. sec .. " cache=" .. tostring(AW.buffCache[slot.spell]) ..
					" -> " .. tostring(AW.IsBuffActive(slot.spell))
			end
		end
	end
	for i = math.max(1, #AW.buffLog - 9), #AW.buffLog do out[#out + 1] = "log: " .. AW.buffLog[i] end
	return out
end

-- A cast of `name` just succeeded: assume its buff is now on (an Aspect replaces the others).
-- Only for spells we track (the ones on your slots).
function AW.NoteCast(name)
	if not name or secret(name) then return end
	if not AW.InCombat() then return end -- out of combat the real lookup is trusted
	if AW.buffCache[name] == nil then return end
	AW.RememberBuff(name, true, nil, "your cast")
end

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
		st.active = AW.IsBuffActive(name) -- e.g. the Aspect you are in
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
