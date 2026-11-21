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

-- Slice border colours (per slot): slot.color is one of these names
AW.COLOR_ORDER = { "white", "green", "red", "pink", "blue", "gold", "purple" }
AW.COLOR_RGB = {
	white = { 1, 1, 1 }, green = { 0.3, 1, 0.35 }, red = { 1, 0.35, 0.35 }, pink = { 1, 0.5, 0.75 },
	blue = { 0.4, 0.7, 1 }, gold = { 1, 0.82, 0.1 }, purple = { 0.72, 0.5, 1 },
}
function AW.SlotColor(slot)
	local c = slot and slot.color and AW.COLOR_RGB[slot.color]
	if c then return c[1], c[2], c[3] end
end

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
-- closeMode: "click" (close after every click), "success" (default: a spell slice stays open until
-- the cast succeeds, so you can keep clicking it; everything else closes on click) or "never".
function AW.SecureAttributes(slot, goPage, closeMode)
	if goPage then return { type = "macro", macrotext = "/click ActionWheelsGo" .. goPage } end
	local a = AW.SlotAttributes(slot)
	local body
	if a.type == "spell" then body = "/cast " .. a.spell
	elseif a.type == "item" then body = "/use " .. a.item
	elseif a.type == "macro" then body = a.macrotext end
	if not body then return {} end
	local close = true
	if closeMode == "never" then close = false
	elseif closeMode == "success" and a.type == "spell" then close = false end
	return { type = "macro", macrotext = close and (body .. "\n" .. AW.CLOSE_LINE) or body }
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

---------------------------------------------------------------------------
-- Items: found by ID. A name only resolves reliably for items the game has cached, so a slot keeps
-- the item's ID (from the drag, or looked up from your bags) and everything uses that.
---------------------------------------------------------------------------
local function itemIdFromLink(link)
	if type(link) ~= "string" then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
end

local function bagItemId(name)
	local getN = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
	if not (getN and getLink) then return nil end
	for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
		local n = getN(bag)
		for slot = 1, (type(n) == "number" and n or 0) do
			local link = getLink(bag, slot)
			if link and string.match(link, "%[(.-)%]") == name then return itemIdFromLink(link) end
		end
	end
end

-- Item ID for a name (nil when the game can't say yet).
function AW.ResolveItemId(name)
	if not name then return nil end
	local id
	if C_Item and C_Item.GetItemInfoInstant then id = (C_Item.GetItemInfoInstant(name)) end
	if not id and GetItemInfoInstant then id = (GetItemInfoInstant(name)) end
	if not id and GetItemInfo then id = itemIdFromLink(select(2, GetItemInfo(name))) end
	if not id then id = bagItemId(name) end
	return id
end

-- The item ID of an item slot; looks it up once and remembers it on the slot.
function AW.ItemIdOf(slot)
	if not (slot and slot.type == "item") then return nil end
	if slot.itemID then return slot.itemID end
	local id = AW.ResolveItemId(slot.item)
	if id then slot.itemID = id end
	return id
end

function AW.ItemIcon(id)
	if not id then return nil end
	if C_Item and C_Item.GetItemIconByID then
		local t = C_Item.GetItemIconByID(id)
		if t then return t end
	end
	if GetItemIcon then
		local t = GetItemIcon(id)
		if t then return t end
	end
	if GetItemInfoInstant then
		local _, _, _, _, icon = GetItemInfoInstant(id)
		return icon
	end
end

-- Fill in missing item IDs on every wheel (called out of combat when the layout is applied).
function AW.ResolveItemIds()
	if not (ActionWheelsDB and ActionWheelsDB.profile) then return end
	for _, w in pairs(AW.P().wheels) do
		for _, slot in pairs(w.items) do
			if slot.type == "item" and not slot.itemID then AW.ItemIdOf(slot) end
		end
	end
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
		-- the action bar's own icon for it, when it is on a bar (what the bar shows is what we show)
		if AW.ActionBarLook then tex = (AW.ActionBarLook(slot.spell)) end
		-- follow the spell as the game sees it now: a replaced / transformed spell has another icon
		local id = (not tex) and AW.SpellIdOf and AW.SpellIdOf(slot.spell)
		if id and C_Spell and C_Spell.GetOverrideSpell and C_Spell.GetSpellTexture then
			local ok, ov = pcall(C_Spell.GetOverrideSpell, id)
			if ok and ov and ov ~= id then
				local ok2, t = pcall(C_Spell.GetSpellTexture, ov)
				if ok2 then tex = t end
			end
		end
		if not tex then
			if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(slot.spell)
			elseif GetSpellTexture then tex = GetSpellTexture(slot.spell) end
		end
	elseif slot.type == "item" then
		tex = AW.ItemIcon(AW.ItemIdOf(slot))
		if not tex and GetItemInfoInstant then
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
		return { type = "item", item = name, itemID = (type(a) == "number") and a or nil }
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
