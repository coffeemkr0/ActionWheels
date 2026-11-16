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

-- Icon to show: explicit slot.icon, else the spell/item/pet-command icon, else a question mark.
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function AW.SlotIcon(slot)
	if AW.IsEmpty(slot) then return nil end
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
