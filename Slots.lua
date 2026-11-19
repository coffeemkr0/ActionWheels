-- Slots: what a wheel slice does. Pure data and string handling (no frames), so it is unit-tested.
ActionWheels = ActionWheels or {}
local AW = ActionWheels

AW.MINSLOTS, AW.MAXSLOTS = 4, 12
AW.MAXWHEELS = 8 -- one pre-built secure page per wheel

-- pet command -> macro line, and the icon the game's own pet bar uses for it
AW.PET_COMMANDS = {
	attack     = { "/petattack",     "Interface\\Icons\\Ability_GhoulFrenzy" },
	follow     = { "/petfollow",     "Interface\\Icons\\Spell_Nature_Spiritwolf" },
	stay       = { "/petstay",       "Interface\\Icons\\Spell_Nature_TimeStop" },
	passive    = { "/petpassive",    "Interface\\Icons\\Ability_Seal" },
	defensive  = { "/petdefensive",  "Interface\\Icons\\Ability_Defend" },
	aggressive = { "/petaggressive", "Interface\\Icons\\Ability_Racial_BloodRage" },
	assist     = { "/petassist",     "Interface\\Icons\\Ability_Hunter_SniperShot" },
}

-- Every secure attribute a slot can set; all are cleared before a slot is (re)applied.
AW.ATTR_KEYS = { "type", "spell", "item", "macrotext" }

function AW.IsEmpty(slot)
	return not slot or not slot.type
end

-- Build a slot from user text; returns slot or nil, error message.
function AW.MakeSlot(kind, arg)
	arg = arg or ""
	if kind == "spell" or kind == "item" then
		if arg == "" then return nil, "Give a " .. kind .. " name." end
		return { type = kind, [kind] = arg }
	elseif kind == "macro" then
		if arg == "" then return nil, "Give the macro text, e.g. /cast Hunter's Mark" end
		return { type = "macro", macrotext = arg }
	elseif kind == "wheel" then
		if arg == "" then return nil, "Give a wheel name or number." end
		return { type = "wheel", wheel = arg } -- Core resolves this to a wheel id
	elseif kind == "pet" then
		local c = string.lower(arg)
		if not AW.PET_COMMANDS[c] then return nil, "Pet command must be: attack, follow, stay, passive, defensive, aggressive or assist." end
		return { type = "pet", pet = c }
	end
	return nil, "Slot type must be spell, item, macro, pet or wheel."
end

-- The secure-button attributes for a slot ({} for an empty or unknown slot).
-- Wheel slots have none: the layout gives them a "subwheel" attribute that the click snippet uses.
function AW.SlotAttributes(slot)
	if AW.IsEmpty(slot) then return {} end
	if slot.type == "spell" and slot.spell then
		return { type = "spell", spell = slot.spell }
	elseif slot.type == "item" and slot.item then
		return { type = "item", item = slot.item }
	elseif slot.type == "macro" and slot.macrotext then
		return { type = "macro", macrotext = slot.macrotext }
	elseif slot.type == "pet" and AW.PET_COMMANDS[slot.pet] then
		return { type = "macro", macrotext = AW.PET_COMMANDS[slot.pet][1] }
	end
	return {}
end

-- What the slice's secure button really gets. Every slice runs as a macro whose last line
-- /click's ActionWheelsClose (a secure handler that hides the wheel), so the wheel closes after the
-- action even in combat. A sub-wheel slice (goPage = the target page number) /click's that page's
-- ActionWheelsGo<k> button instead and leaves the wheel open.
AW.CLOSE_LINE = "/click ActionWheelsClose"
function AW.SecureAttributes(slot, goPage)
	if goPage then return { type = "macro", macrotext = "/click ActionWheelsGo" .. goPage } end
	local a = AW.SlotAttributes(slot)
	local body
	if a.type == "spell" then body = "/cast " .. a.spell
	elseif a.type == "item" then body = "/use " .. a.item
	elseif a.type == "macro" then body = a.macrotext end
	if not body then return {} end
	return { type = "macro", macrotext = body .. "\n" .. AW.CLOSE_LINE }
end

-- Short text for the hub and for /aw list.
function AW.DescribeSlot(slot)
	if AW.IsEmpty(slot) then return "(empty)" end
	if slot.label and slot.label ~= "" then return slot.label end
	if slot.type == "pet" then return "Pet: " .. tostring(slot.pet) end
	if slot.type == "wheel" then
		local w = ActionWheelsDB and ActionWheelsDB.profile and ActionWheelsDB.profile.wheels[slot.wheel]
		return "Wheel: " .. (w and w.name or tostring(slot.wheel))
	end
	return tostring(slot[slot.type] or slot.type)
end

---------------------------------------------------------------------------
-- #showtooltip: a macro slot that borrows the look and live state of the spell / item it uses
---------------------------------------------------------------------------
-- Pick one option out of "[cond] A; [cond2] B; C". Uses the game's own parser when present so
-- conditionals ([mod:shift], [combat], [mounted]...) are evaluated for real.
local function pickOption(arg)
	if SecureCmdOptionParse then
		local ok, result = pcall(SecureCmdOptionParse, arg)
		if ok then
			if type(result) ~= "string" or result == "" then return nil end
			return result
		end
	end
	-- no parser (tests, odd clients): the unconditional default clause, else the first clause
	local first, default
	for clause in string.gmatch(arg, "[^;]+") do
		clause = string.gsub(clause, "^%s+", "")
		first = first or clause
		if not string.find(clause, "^%[") then default = clause end
	end
	local pick = default or first
	if not pick then return nil end
	return (string.gsub(pick, "^%b[]%s*", ""))
end

local function cleanName(n)
	n = string.gsub(n or "", "^%s+", "")
	n = string.gsub(n, "%s+$", "")
	n = string.gsub(n, "^!", "") -- "!Name" = don't toggle off
	n = string.gsub(n, "%s*%(Rank %d+%)$", "")
	n = string.gsub(n, "%s*%(Rank %d+%)$", "")
	return n ~= "" and n or nil
end

local function isSpell(name)
	if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) ~= nil end
	if GetSpellInfo then return GetSpellInfo(name) ~= nil end
	return false
end

-- The "virtual slot" ({type="spell"...} or {type="item"...}) a macro's #showtooltip points at, or nil.
-- "#showtooltip" alone means: the first spell / item the macro casts or uses.
function AW.MacroTooltipSlot(macrotext)
	if type(macrotext) ~= "string" then return nil end
	local arg
	for line in string.gmatch(macrotext, "[^\n]+") do
		local a = string.match(line, "^%s*[#/]showtooltip%s*(.-)%s*$") or string.match(line, "^%s*#show%s*(.-)%s*$")
		if a then arg = a break end
	end
	if not arg then return nil end
	if arg == "" then
		for line in string.gmatch(macrotext, "[^\n]+") do
			local cmd, rest = string.match(line, "^%s*/(%a+)%s+(.+)$")
			cmd = cmd and string.lower(cmd)
			if cmd == "cast" or cmd == "use" or cmd == "castrandom" or cmd == "cast" then arg = rest break end
		end
		if arg == "" then return nil end
	end
	local name = cleanName(pickOption(arg))
	if not name then return nil end
	if tonumber(name) then return nil end -- slot numbers / ids: not supported
	if isSpell(name) then return { type = "spell", spell = name } end
	return { type = "item", item = name }
end

-- Icon to show: explicit slot.icon, else the spell/item/pet-command icon, else a question mark.
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function AW.SlotIcon(slot)
	if AW.IsEmpty(slot) then return nil end
	if slot.type == "macro" then
		local v = AW.MacroTooltipSlot(slot.macrotext)
		if v then return AW.SlotIcon({ type = v.type, spell = v.spell, item = v.item }) end
	end
	if slot.icon and slot.icon ~= "" then return slot.icon end
	if slot.type == "pet" and AW.PET_COMMANDS[slot.pet] then return AW.PET_COMMANDS[slot.pet][2] end
	if slot.type == "wheel" then return "Interface\\Icons\\INV_Misc_Map_01" end
	local tex
	if slot.type == "spell" then
		if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(slot.spell)
		elseif GetSpellTexture then tex = GetSpellTexture(slot.spell) end
	elseif slot.type == "item" then
		if GetItemInfoInstant then
			local _, _, _, _, icon = GetItemInfoInstant(slot.item)
			tex = icon
		end
	end
	return tex or QUESTION
end

---------------------------------------------------------------------------
-- Dragging things from the game onto a slot
---------------------------------------------------------------------------
local PET_TOKENS = {
	PET_ACTION_ATTACK = "attack", PET_ACTION_FOLLOW = "follow", PET_ACTION_WAIT = "stay",
	PET_MODE_PASSIVE = "passive", PET_MODE_DEFENSIVE = "defensive", PET_MODE_ASSIST = "assist",
	PET_MODE_AGGRESSIVE = "aggressive",
}

local function spellName(id, index, book)
	if id then
		if C_Spell and C_Spell.GetSpellName then
			local n = C_Spell.GetSpellName(id)
			if n then return n end
		end
		if GetSpellInfo then
			local n = GetSpellInfo(id)
			if n then return n end
		end
	end
	if index and book then
		if C_SpellBook and C_SpellBook.GetSpellBookItemName then
			local n = C_SpellBook.GetSpellBookItemName(index, book)
			if n then return n end
		end
		if GetSpellBookItemName then return (GetSpellBookItemName(index, book)) end
	end
end

AW.SpellName = spellName

-- What is on the mouse cursor, as a slot: returns slot, or nil and a reason.
function AW.SlotFromCursor()
	if not GetCursorInfo then return nil, "nothing on the cursor" end
	local kind, a, b, c = GetCursorInfo()
	if kind == "spell" then
		local id = (type(c) == "number" and c) or (type(a) == "number" and b == nil and a) or nil
		local name = spellName(id, a, b)
		if not name then return nil, "couldn't read that spell" end
		return { type = "spell", spell = name }
	elseif kind == "item" then
		local name
		if GetItemInfo then name = (GetItemInfo(a)) end
		if not name and type(b) == "string" then name = string.match(b, "%[(.-)%]") end
		if not name then return nil, "couldn't read that item (try again in a moment)" end
		return { type = "item", item = name }
	elseif kind == "macro" then
		local name, icon, body = GetMacroInfo(a)
		if not body then return nil, "couldn't read that macro" end
		return { type = "macro", macrotext = body, label = name, icon = icon }
	elseif kind == "petaction" then
		local name, _, isToken, _, _, _, spellId
		if GetPetActionInfo then name, _, isToken, _, _, _, spellId = GetPetActionInfo(a) end
		if name and PET_TOKENS[name] then return { type = "pet", pet = PET_TOKENS[name] } end
		local sname = spellName(spellId)
		if sname then return { type = "macro", macrotext = "/cast " .. sname, label = sname } end
		return nil, "couldn't read that pet action"
	end
	return nil, "drag a spell, item or macro onto a slot"
end

-- Macro-conditional text that decides when a wheel opens first, e.g. [mounted] or [stance:1,combat].
function AW.ValidCondition(cond)
	if type(cond) ~= "string" then return false end
	cond = string.gsub(cond, "^%s+", "")
	cond = string.gsub(cond, "%s+$", "")
	if cond == "" or string.len(cond) > 120 then return false end
	while cond ~= "" do
		local g, rest = string.match(cond, "^(%b[])(.*)$")
		if not g or not string.find(g, "^%[[%w:,/_ !~%-]+%]$") then return false end
		cond = rest
	end
	return true
end
