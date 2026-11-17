-- Run via tests/run_tests.py (Lua 5.1 through lupa). Run from the repo root.
dofile("tests/wow_stubs.lua")
for _, f in ipairs({ "Core", "Slots", "State", "Defaults", "Wheel", "Share", "Minimap", "Config" }) do
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
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/petattack\n/click ActionWheelsClose", "slice 1 macro text closes the wheel")
eq(_G.ActionWheelsP1S7:GetAttribute("macrotext"), "/use Hearthstone\n/click ActionWheelsClose", "slice 7 is Hearthstone")
eq(_G.ActionWheelsClose ~= nil, true, "close button exists"); eq(_G.ActionWheelsGo1 ~= nil, true, "page button exists")
eq(#_WRAPS, 0, "no click wrapping any more")

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
eq(_G.ActionWheelsP1S4:GetAttribute("macrotext"), "/petpassive\n/click ActionWheelsClose", "attributes untouched in combat")
_COMBAT = false
AW.OnEvent(nil, "PLAYER_REGEN_ENABLED")
eq(AW.pendingApply, false, "layout applied when combat ends")
eq(_G.ActionWheelsP1S4:GetAttribute("macrotext"), "/cast Multi-Shot\n/click ActionWheelsClose", "attribute applied after combat")
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/cast Aimed Shot\n/click ActionWheelsClose", "slice 1 changed to a spell, old macro replaced")
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
eq(_G.ActionWheelsP1S8:GetAttribute("macrotext"), "/click ActionWheelsGo2", "sub-wheel slice clicks the page button")
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
eq(AW.SecureAttributes({ type = "macro", macrotext = "/x" }).macrotext, "/x\n/click ActionWheelsClose", "macro slots get the close line")
eq(next(AW.SecureAttributes(nil)), nil, "empty slots have no secure attributes")

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

-- active buffs (e.g. the current Aspect)
UnitAura = function(_, i) return ({ "Aspect of the Hawk", "Mark of the Wild" })[i] end
eq(AW.SlotState({ type = "spell", spell = "Aspect of the Hawk" }).active, true, "active buff found (UnitAura)")
eq(AW.SlotState({ type = "spell", spell = "Aspect of the Monkey" }).active, false, "inactive buff")
UnitAura = nil
AuraUtil = { FindAuraByName = function(n) if n == "A" then return "A" end end }
eq(AW.SlotState({ type = "spell", spell = "A" }).active, true, "active buff found (AuraUtil)")
AuraUtil = nil
C_UnitAuras = { GetAuraDataBySpellName = function(_, n) if n == "B" then return {} end end }
eq(AW.SlotState({ type = "spell", spell = "B" }).active, true, "active buff found (C_UnitAuras)")
eq(AW.SlotState({ type = "spell", spell = "C" }).active, false, "inactive buff (C_UnitAuras)")
C_UnitAuras = nil

-- secret values (combat): never compare or branch on them
local SECRET = {}
local function mk() return setmetatable({}, SECRET) end
issecretvalue = function(v) return getmetatable(v) == SECRET end
C_Spell = {
	GetSpellCooldown = function() return { startTime = mk(), duration = mk(), isOnGCD = false } end,
	GetSpellCharges = function() return { currentCharges = mk(), maxCharges = mk() } end,
	IsSpellUsable = function() return mk(), mk() end,
	IsSpellInRange = function() return mk() end,
}
local sec = AW.SlotState({ type = "spell", spell = "X" })
eq(sec.cdSecret, true, "secret cooldown flagged")
eq(sec.count, nil, "secret charges ignored")
eq(sec.usable, nil, "secret usable ignored")
eq(sec.inRange, nil, "secret range ignored")
C_Spell.GetSpellCooldown = function() return { startTime = mk(), duration = mk(), isOnGCD = true } end
eq(AW.SlotState({ type = "spell", spell = "X" }).cdSecret, nil, "secret global cooldown hidden via isOnGCD")
C_Spell.GetSpellCooldown = function() return { startTime = mk(), duration = mk(), isOnGCD = false } end
-- the item path with secrets
GetItemCooldown = function() return mk(), mk() end
GetItemCount = function() return mk() end
IsUsableItem = function() return mk(), mk() end
IsItemInRange = function() return mk() end
local si = AW.SlotState({ type = "item", item = "Hearthstone" })
eq(si.cdSecret, true, "secret item cooldown flagged"); eq(si.count, nil, "secret item count ignored")
-- painting a secret cooldown must not error
AW.Slash("reset")
AW.Slash("set 1 spell Aimed Shot")
_G.ActionWheelsPage1:Show()
local okPaint = pcall(AW.RefreshStates)
eq(okPaint, true, "refresh survives secret values")
C_Spell, issecretvalue = nil, nil

-- buff memory in combat: the lookup goes blind, the cache keeps the last known state
AW.buffCache = {}
UnitAura = function(_, i) return ({ "Aspect of the Hawk" })[i] end
eq(AW.IsBuffActive("Aspect of the Hawk"), true, "buff seen out of combat")
_COMBAT = true
UnitAura = function() return nil end -- the game stops answering
eq(AW.IsBuffActive("Aspect of the Hawk"), true, "remembered in combat")
eq(AW.SlotState({ type = "spell", spell = "Aspect of the Hawk" }).active, true, "slot shows the remembered buff")
GetSpellInfo = function(id) return ({ [1] = "Aspect of the Monkey" })[id] end
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
eq(AW.IsBuffActive("Aspect of the Monkey"), true, "a successful aspect cast turns it on")
eq(AW.IsBuffActive("Aspect of the Hawk"), false, "and the other aspect off")
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 1) -- other units ignored
_COMBAT = false
eq(AW.IsBuffActive("Aspect of the Monkey"), false, "out of combat the real lookup wins")
UnitAura = nil
AW.OnEvent(nil, "UNIT_AURA", "player")
AW.OnEvent(nil, "UNIT_AURA", "party1")

-- the refresh loop runs on shown pages without errors
AW.Slash("reset")
AW.Slash("set 1 spell Aimed Shot")
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.cdStart, 100, "refresh painted the cooldown on the shown page")


-- ===== milestone 3 / 4 =====
AW.Slash("reset")

-- dragging from the game
GetCursorInfo = function() return "spell", 3, "spell", 19434 end
GetSpellInfo = function(id) return id == 19434 and "Aimed Shot" or nil end
eq(AW.SlotFromCursor().spell, "Aimed Shot", "drag a spell (classic shape)")
C_Spell = { GetSpellName = function(id) return "Arcane Shot" end }
eq(AW.SlotFromCursor().spell, "Arcane Shot", "drag a spell (modern name lookup)")
C_Spell = nil
GetCursorInfo = function() return "spell", 19434, nil, nil end
eq(AW.SlotFromCursor().spell, "Aimed Shot", "drag a spell given only its id")
GetCursorInfo = function() return "item", 6948, "|cffffffff|Hitem:6948|h[Hearthstone]|h|r" end
GetItemInfo = function() return nil end
eq(AW.SlotFromCursor().item, "Hearthstone", "drag an item (name from the link)")
GetItemInfo = function(id) return "Hearth" end
eq(AW.SlotFromCursor().item, "Hearth", "drag an item (name from the cache)")
GetCursorInfo = function() return "macro", 1 end
GetMacroInfo = function() return "Mark", 132212, "/cast Hunter's Mark\n/petattack" end
local ms = AW.SlotFromCursor()
eq(ms.type, "macro", "drag a macro"); eq(ms.label, "Mark", "macro keeps its name"); eq(ms.icon, 132212, "macro keeps its icon")
GetCursorInfo = function() return "petaction", 1 end
GetPetActionInfo = function() return "PET_ACTION_ATTACK" end
eq(AW.SlotFromCursor().pet, "attack", "drag the pet attack button")
GetPetActionInfo = function() return "Growl", nil, false, nil, nil, nil, 2649 end
GetSpellInfo = function(id) return id == 2649 and "Growl" or nil end
eq(AW.SlotFromCursor().macrotext, "/cast Growl", "drag a pet ability")
GetCursorInfo = function() return nil end
eq(AW.SlotFromCursor(), nil, "empty cursor")

GetCursorInfo = function() return "spell", 3, "spell", 19434 end
GetSpellInfo = function(id) return "Aimed Shot" end
local cleared = _CLEARED
eq(AW.DropOnSlot("main", 2), true, "drop onto a slot")
eq(AW.P().wheels.main.items[2].spell, "Aimed Shot", "dropped spell stored")
eq(_G.ActionWheelsP1S2:GetAttribute("macrotext"), "/cast Aimed Shot\n/click ActionWheelsClose", "dropped spell reaches the secure button")
eq(_CLEARED, cleared + 1, "cursor cleared after the drop")
_COMBAT = true
eq(AW.DropOnSlot("main", 3), false, "no drops in combat")
_COMBAT = false
GetCursorInfo = function() return nil end

-- auto-open conditions
eq(AW.ValidCondition("[mounted]"), true, "simple condition")
eq(AW.ValidCondition("[stance:1,combat]"), true, "condition with args")
eq(AW.ValidCondition("[mounted][swimming]"), true, "alternatives")
eq(AW.ValidCondition("mounted"), false, "needs brackets")
eq(AW.ValidCondition("[mounted] page9"), false, "no trailing text")
eq(AW.ValidCondition("[a;b]"), false, "no semicolons")
eq(AW.ValidCondition(""), false, "empty")
AW.Slash("wheel new Mount")
AW.Slash("wheel auto [mounted]")
eq(AW.P().wheels.w2.auto, "[mounted]", "auto stored")
AW.Slash("wheel select 1")
eq(_STATEDRV.autopage, "[mounted] page2; page1", "state driver registered with the default last")
AW.Slash("wheel select 2")
eq(_STATEDRV.autopage, "[mounted] page2; page2", "default follows the selected wheel")
AW.Slash("wheel auto [bad;x]")
eq(AW.P().wheels.w2.auto, "[mounted]", "invalid condition rejected")
AW.Slash("wheel auto off")
eq(_STATEDRV.autopage, nil, "driver removed when no wheel has a condition")

-- share: round trip and sanitising
AW.Slash("wheel select 1")
AW.Slash("set 3 macro /cast Hunter's Mark")
AW.P().wheels.main.items[4] = { type = "macro", macrotext = "/a\n/b", icon = "Ability_Hunter_Pet_Wolf", label = "Two" }
AW.Slash("set 8 wheel 2")
local str = AW.ExportWheels({ "main" })
eq(string.sub(str, 1, 4), "AW1:", "export prefix")
local pre = AW.PreviewImport(str)
eq(pre.wheels[1].items[1].pet, "attack", "round trip keeps pet slots")
eq(pre.wheels[1].items[8], nil, "wheel links are not exported")
eq(#pre.macros, 2, "macros listed for the confirmation")
eq(pre.wheels[1].items[4].macrotext, "/a\n/b", "macro newlines survive")
eq(pre.wheels[1].items[4].icon, "Interface\\Icons\\Ability_Hunter_Pet_Wolf", "plain icon names are expanded")
local before = #AW.P().order
local ids = AW.CommitImport(pre)
eq(#ids, 1, "import adds a wheel"); eq(#AW.P().order, before + 1, "wheel count grows")
eq(AW.PreviewImport("garbage"), nil, "garbage rejected")
eq(AW.PreviewImport("AW1:{s00;"), nil, "truncated rejected")
local hostile = AW.Serialize({ v = 1, wheels = { { name = "x\1bad", slots = 99, auto = "[a;b]", items = {
	{ type = "wheel", wheel = "w1" }, { type = "spell", spell = "A\1B", icon = "..\\..\\x" }, { type = "pet", pet = "dance" },
	{ type = "os", os = "execute" }, { type = "macro", macrotext = string.rep("x", 300) } } } } })
local h = AW.PreviewImport(hostile).wheels[1]
eq(h.slots, 12, "hostile slots clamped"); eq(h.auto, nil, "hostile auto dropped")
eq(h.items[1], nil, "wheel link dropped"); eq(h.items[2].spell, "AB", "control chars stripped")
eq(h.items[2].icon, nil, "path-traversal icon dropped"); eq(h.items[3], nil, "bad pet dropped")
eq(h.items[4], nil, "unknown type dropped"); eq(#h.items[5].macrotext, 255, "macro length capped")
for _ = 1, 12 do AW.Slash("wheel new Fill") end
eq(#AW.CommitImport(pre), 0, "import stops at the wheel limit")

-- per-character wheels
AW.Slash("reset")
eq(AW.UsingCharProfile(), false, "account profile by default")
AW.Slash("set 1 spell Account Spell")
AW.SetCharProfile(true)
eq(AW.UsingCharProfile(), true, "character profile on")
eq(AW.P().wheels.main.items[1].spell, "Account Spell", "character copy starts from the account wheels")
AW.Slash("set 1 spell Char Spell")
eq(ActionWheelsDB.profile.wheels.main.items[1].spell, "Account Spell", "account wheels untouched")
AW.SetCharProfile(false)
eq(AW.P().wheels.main.items[1].spell, "Account Spell", "switching back restores the account wheels")
AW.SetCharProfile(true)
eq(AW.P().wheels.main.items[1].spell, "Char Spell", "character wheels are kept")
AW.SetCharProfile(false)

-- windows build and behave with the stubs
AW.ShowConfig()
eq(AW.ConfigShown(), true, "settings window opens")
AW.RefreshConfig()
AW.OnEvent(nil, "PLAYER_REGEN_DISABLED")
eq(AW.ConfigShown(), false, "settings window closes when combat starts")
_COMBAT = true
AW.ShowConfig()
eq(AW.ConfigShown(), false, "settings window refuses to open in combat")
_COMBAT = false
AW.Slash("minimap")
eq(ActionWheelsDB.minimap.hide, true, "minimap toggled off")
AW.Slash("minimap")
AW.Slash("")
eq(AW.ConfigShown(), true, "/aw opens the settings window")

-- sanitize fills defaults and clamps slot counts
ActionWheelsDB = { profile = { wheels = { main = { name = "M", slots = 99, items = {} } }, order = { "main" }, current = "gone", settings = {} } }
AW.InitDB()
eq(AW.P().wheels.main.slots, 12, "sanitize clamps slots")
eq(AW.P().current, "main", "sanitize repairs current wheel")
eq(AW.P().settings.openMode, "toggle", "sanitize fills settings")

print(total .. " checks, " .. fails .. " failed")
if fails > 0 then error("tests failed") end
