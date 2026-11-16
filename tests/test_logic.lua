-- Run via tests/run_tests.py (Lua 5.1 through lupa). Run from the repo root.
dofile("tests/wow_stubs.lua")
for _, f in ipairs({ "Core", "Slots", "Defaults", "Wheel" }) do
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
eq(_G.ActionWheelsSlice1:GetAttribute("type"), "macro", "slice 1 is the pet attack macro")
eq(_G.ActionWheelsSlice1:GetAttribute("macrotext"), "/petattack", "slice 1 macro text")
eq(_G.ActionWheelsSlice7:GetAttribute("item"), "Hearthstone", "slice 7 is Hearthstone")
eq(#_WRAPS, AW.MAXSLOTS, "every slice is wrapped to close the wheel")

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
eq(_G.ActionWheelsSlice4:GetAttribute("macrotext"), "/petpassive", "attributes untouched in combat")
_COMBAT = false
AW.OnEvent(nil, "PLAYER_REGEN_ENABLED")
eq(AW.pendingApply, false, "layout applied when combat ends")
eq(_G.ActionWheelsSlice4:GetAttribute("spell"), "Multi-Shot", "attribute applied after combat")
eq(_G.ActionWheelsSlice1:GetAttribute("spell"), "Aimed Shot", "slice 1 changed to a spell")
eq(_G.ActionWheelsSlice1:GetAttribute("macrotext"), nil, "old macro text cleared")
eq(_G.ActionWheelsToggle:GetAttribute("mode"), "hold", "toggle button got the open mode")
eq(ActionWheelsDB.profile.wheels.main.items[4].spell, "Multi-Shot", "deferred slot persisted")

-- reset
AW.Slash("reset")
eq(AW.P().wheels.main.items[1].pet, "attack", "reset restores the starter wheel")

-- sanitize fills defaults and clamps slot counts
ActionWheelsDB = { profile = { wheels = { main = { name = "M", slots = 99, items = {} } }, order = { "main" }, current = "gone", settings = {} } }
AW.InitDB()
eq(AW.P().wheels.main.slots, 12, "sanitize clamps slots")
eq(AW.P().current, "main", "sanitize repairs current wheel")
eq(AW.P().settings.openMode, "toggle", "sanitize fills settings")

print(total .. " checks, " .. fails .. " failed")
if fails > 0 then error("tests failed") end
