-- Run via tests/run_tests.py (Lua 5.1 through lupa). Run from the repo root.
dofile("tests/wow_stubs.lua")
for _, f in ipairs({ "Core", "Slots", "State", "Defaults", "Wheel" }) do
	assert(loadfile(f .. ".lua"), f)()
end
local AW = ActionWheels
local fails, total = 0, 0
local function eq(a, b, name)
	total = total + 1
	if a ~= b then fails = fails + 1; print("FAIL " .. name .. ": expected " .. tostring(b) .. " got " .. tostring(a)) end
end
local function lastPrinted() return _PRINTED[#_PRINTED] end

-- slot construction and secure attributes
local s = AW.MakeSlot("spell", "Aimed Shot")
eq(AW.SlotAttributes(s).type, "spell", "spell type")
eq(AW.SlotAttributes(s).spell, "Aimed Shot", "spell name")
eq(AW.SlotAttributes(AW.MakeSlot("item", "Hearthstone")).item, "Hearthstone", "item name")
eq(AW.SlotAttributes(AW.MakeSlot("macro", "/cast X")).macrotext, "/cast X", "macro text")
local pet = AW.SlotAttributes(AW.MakeSlot("pet", "Attack"))
eq(pet.type, "macro", "pet is a macro")
eq(pet.macrotext, "/petattack", "pet attack line")
eq(AW.MakeSlot("pet", "dance"), nil, "bad pet command")
eq(AW.MakeSlot("spell", ""), nil, "empty spell name")
eq(AW.MakeSlot("potion", "x"), nil, "unknown type")
eq(next(AW.SlotAttributes(nil)), nil, "empty slot has no attributes")
eq(next(AW.SlotAttributes({ type = "pet", pet = "bogus" })), nil, "bogus pet has no attributes")
eq(AW.SlotIcon(s), "Interface\\Icons\\Spell_Aimed Shot", "spell icon lookup")
eq(AW.SlotIcon({ type = "spell", spell = "X", icon = "foo" }), "foo", "explicit icon wins")
eq(AW.SlotIcon(AW.MakeSlot("pet", "follow")), AW.PET_COMMANDS.follow[2], "pet icon")
eq(AW.SlotIcon(nil), nil, "empty slot has no icon")
eq(AW.DescribeSlot(AW.MakeSlot("pet", "stay")), "Pet: stay", "describe pet")
eq(AW.DescribeSlot(nil), "(empty)", "describe empty")

-- profile
AW.OnEvent(nil, "ADDON_LOADED", "SomethingElse")
eq(ActionWheelsDB, nil, "other addons do not init the DB")
AW.OnEvent(nil, "ADDON_LOADED", "ActionWheels")
eq(#AW.P().wheels.main.items, 8, "starter wheel has 8 slots")
AW.OnEvent(nil, "PLAYER_LOGIN")
eq(_G.ActionWheelsP1S1:GetAttribute("type"), "macro", "slice 1 is the pet attack macro")
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/petattack", "slice 1 macro text")
eq(_G.ActionWheelsP1S7:GetAttribute("item"), "Hearthstone", "slice 7 is Hearthstone")
eq(#_WRAPS, AW.MAXSLOTS, "every slice of the first page is wrapped")

-- slash: set / clear / combat deferral
AW.Slash("set 1 spell Aimed Shot")
eq(AW.P().wheels.main.items[1].spell, "Aimed Shot", "slash set stored")
AW.Slash("set 99 spell X")
eq(lastPrinted(), "|cff33ff99ActionWheels:|r Slot must be a number from 1 to 8.", "slot range checked")
AW.Slash("set 2 pet nope")
eq(AW.P().wheels.main.items[2].pet, "follow", "bad pet command leaves the slot alone")
AW.Slash("clear 3")
eq(AW.P().wheels.main.items[3], nil, "slash clear")
AW.Slash("slots 40")
eq(AW.P().wheels.main.slots, 12, "slots clamped to max")
AW.Slash("slots 1")
eq(AW.P().wheels.main.slots, 4, "slots clamped to min")
AW.Slash("slots 8")
AW.Slash("mode hold")
eq(AW.P().settings.openMode, "hold", "mode hold")
AW.Slash("mode sideways")
eq(AW.P().settings.openMode, "hold", "bad mode ignored")
AW.Slash("scale 9")
eq(AW.P().settings.scale, 2, "scale clamped")

-- combat: nothing changes until combat ends
_COMBAT = true
AW.Slash("set 4 spell Multi-Shot")
eq(AW.P().wheels.main.items[4].spell, "Multi-Shot", "data updates in combat")
eq(AW.pendingApply, true, "layout deferred in combat")
eq(_G.ActionWheelsP1S4:GetAttribute("macrotext"), "/petpassive", "attributes untouched in combat")
_COMBAT = false
AW.OnEvent(nil, "PLAYER_REGEN_ENABLED")
eq(AW.pendingApply, false, "layout applied when combat ends")
eq(_G.ActionWheelsP1S4:GetAttribute("spell"), "Multi-Shot", "attribute applied after combat")
eq(_G.ActionWheelsP1S1:GetAttribute("spell"), "Aimed Shot", "slice 1 changed to a spell")
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), nil, "old macro text cleared")
eq(_G.ActionWheelsToggle:GetAttribute("mode"), "hold", "toggle button got the open mode")
eq(ActionWheelsDB.profile.wheels.main.items[4].spell, "Multi-Shot", "deferred slot persisted")

-- wheels and sub-wheels
AW.Slash("reset")
AW.Slash("wheel new Extra")
eq(#AW.P().order, 2, "second wheel created")
eq(AW.P().current, "w2", "new wheel selected")
eq(_G.ActionWheelsPage2:GetAttribute("next"), "page1", "page 2 pages forward to page 1")
eq(_G.ActionWheelsPage1:GetAttribute("prev"), "page2", "page 1 pages back to page 2")
eq(_G.ActionWheelsRoot:GetAttribute("home"), "page2", "the selected wheel opens first")
AW.Slash("wheel select 1")
AW.Slash("set 8 wheel Extra")
eq(AW.P().wheels.main.items[8].wheel, "w2", "wheel slot resolves the name to an id")
eq(_G.ActionWheelsP1S8:GetAttribute("subwheel"), "page2", "slice links to page 2")
eq(_G.ActionWheelsP1S8:GetAttribute("type"), nil, "sub-wheel slice has no secure action")
eq(_G.ActionWheelsRoot:GetAttribute("home"), "page1", "home follows the selection")
eq(_G.ActionWheelsRoot:GetAttribute("cur"), "page1", "current page reset to home")
AW.Slash("set 8 wheel Main")
eq(AW.P().wheels.main.items[8].wheel, "w2", "a wheel can't open itself (slot unchanged)")
AW.Slash("set 8 wheel Nowhere")
eq(AW.P().wheels.main.items[8].wheel, "w2", "unknown wheel rejected (slot unchanged)")
AW.Slash("set 8 wheel 2")
eq(AW.P().wheels.main.items[8].wheel, "w2", "wheel slot by number")
AW.Slash("wheel select Extra")
AW.Slash("wheel rename Spare")
eq(AW.P().wheels.w2.name, "Spare", "rename")
AW.Slash("wheel delete")
eq(#AW.P().order, 1, "wheel deleted")
eq(AW.P().wheels.main.items[8], nil, "links to the deleted wheel are cleared")
eq(AW.P().current, "main", "selection falls back to the first wheel")
AW.Slash("wheel delete")
eq(#AW.P().order, 1, "the last wheel can't be deleted")
for i = 1, 12 do AW.Slash("wheel new W" .. i) end
eq(#AW.P().order, AW.MAXWHEELS, "wheel count capped")

-- reset
AW.Slash("reset")
eq(AW.P().wheels.main.items[1].pet, "attack", "reset restores the starter wheel")

-- live state: classic-style API
GetSpellCooldown = function(n) return 100, 10, 1 end
GetSpellCharges = function(n) return nil end
IsUsableSpell = function(n) return true, false end
IsSpellInRange = function(n) return 0 end
local st = AW.SlotState({ type = "spell", spell = "Aimed Shot" })
eq(st.cdStart, 100, "cooldown start")
eq(st.cdDur, 10, "cooldown duration")
eq(st.usable, true, "usable")
eq(st.inRange, false, "out of range")
local r, g = AW.StateTint(st)
eq(r, 1, "out of range tints red"); eq(g, 0.3, "out of range tints red (green channel)")
GetSpellCooldown = function() return 100, 1.5, 1 end
eq(AW.SlotState({ type = "spell", spell = "X" }).cdStart, nil, "global cooldown is not shown")
IsUsableSpell = function() return false, true end
local _, _, bl = AW.StateTint(AW.SlotState({ type = "spell", spell = "X" }))
eq(bl, 1, "not enough mana tints blue")
IsUsableSpell = function() return false, false end
local _, _, _, desat = AW.StateTint(AW.SlotState({ type = "spell", spell = "X" }))
eq(desat, true, "unusable is greyed out")
GetSpellCooldown = function() return 100, 8, 1 end
GetSpellCharges = function() return 2, 3 end
local ch = AW.SlotState({ type = "spell", spell = "X" })
eq(ch.count, 2, "charges shown as a count")
eq(ch.cdStart, nil, "no cooldown swirl while a charge remains")
GetSpellCharges = function() return 0, 3 end
eq(AW.SlotState({ type = "spell", spell = "X" }).cdStart, 100, "swirl once charges run out")
-- items
GetItemInfoInstant = function() return 6948 end
GetItemCooldown = function(id) return 50, 30, 1 end
GetItemCount = function() return 0 end
IsUsableItem = function() return true, false end
local it = AW.SlotState({ type = "item", item = "Hearthstone" })
eq(it.cdDur, 30, "item cooldown"); eq(it.count, 0, "item count"); eq(it.usable, false, "no items left is unusable")
-- modern API shapes
C_Spell = {
	GetSpellCooldown = function() return { startTime = 7, duration = 20 } end,
	GetSpellCharges = function() return { currentCharges = 1, maxCharges = 2 } end,
	IsSpellUsable = function() return true, false end,
	IsSpellInRange = function() return true end,
}
local m = AW.SlotState({ type = "spell", spell = "X" })
eq(m.count, 1, "modern charges"); eq(m.cdStart, nil, "modern: charge left, no swirl"); eq(m.inRange, true, "modern range")
C_Spell = nil
eq(next(AW.SlotState({ type = "macro", macrotext = "/x" })), nil, "macros have no live state")

-- the refresh loop runs on shown pages without errors
AW.Slash("reset")
AW.Slash("set 1 spell Aimed Shot")
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.cdStart, 100, "refresh painted the cooldown on the shown page")

-- sanitize fills defaults and clamps slot counts
ActionWheelsDB = { profile = { wheels = { main = { name = "M", slots = 99, items = {} } }, order = { "main" }, current = "gone", settings = {} } }
AW.InitDB()
eq(AW.P().wheels.main.slots, 12, "sanitize clamps slots")
eq(AW.P().current, "main", "sanitize repairs current wheel")
eq(AW.P().settings.openMode, "toggle", "sanitize fills settings")

print(total .. " checks, " .. fails .. " failed")
if fails > 0 then error("tests failed") end
