-- Run via tests/run_tests.py (Lua 5.1 through lupa). Run from the repo root.
dofile("tests/wow_stubs.lua")
for _, f in ipairs({ "Core", "Slots", "State", "Defaults", "Wheel", "Tracker", "Share", "Minimap", "Config" }) do
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
eq(_G.ActionWheelsP1S4:GetAttribute("macrotext"), "/cast Multi-Shot", "attribute applied after combat")
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/cast Aimed Shot", "slice 1 changed to a spell, old macro replaced")
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
AW.buffCache["Aspect of the Monkey"] = false -- tracked: it is on a slot
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

-- the targeted player-aura lookup and instance-id tracking
AW.buffCache, AW.auraInstance, AW.spellIdCache = {}, {}, {}
local HAWK = 13165
local present = true
C_Spell = { GetSpellInfo = function(n) if n == "Aspect of the Hawk" then return { spellID = HAWK } end end }
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if id == HAWK and present then return { auraInstanceID = 77 } end end }
eq(AW.IsBuffActive("Aspect of the Hawk"), true, "targeted lookup finds the buff")
eq(AW.auraInstance[77], "Aspect of the Hawk", "instance id remembered")
present = false
eq(AW.IsBuffActive("Aspect of the Hawk"), false, "targeted lookup says off out of combat")
present = true
AW.IsBuffActive("Aspect of the Hawk")
_COMBAT = true
present = false
C_Secrets = { ShouldSpellAuraBeSecret = function() return false end }
eq(AW.IsBuffActive("Aspect of the Hawk"), true, "an empty answer in combat never turns a buff off")
AW.buffCache["Aspect of the Hawk"] = true
AW.auraInstance[77] = "Aspect of the Hawk"
AW.OnEvent(nil, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 77 } })
eq(AW.IsBuffActive("Aspect of the Hawk"), false, "removal tracked by auraInstanceID")
AW.OnEvent(nil, "UNIT_AURA", "player", { addedAuras = { { name = "Aspect of the Hawk", spellId = HAWK, auraInstanceID = 78 } } })
eq(AW.IsBuffActive("Aspect of the Hawk"), true, "readable addition tracked")
-- exclusivity and log
AW.RememberBuff("Aspect of the Monkey", true, nil, "test")
eq(AW.buffCache["Aspect of the Hawk"], false, "turning one Aspect on turns the others off")
AW.RememberBuff("Aspect of the Hawk", true, nil, "test")
eq(AW.buffCache["Aspect of the Monkey"], false, "and back")
eq(#AW.buffLog > 0, true, "changes are logged")
AW.NoteCast("Untracked Spell")
eq(AW.buffCache["Untracked Spell"], nil, "casts of spells we don't track are ignored")
eq(AW.auraInstance[78], "Aspect of the Hawk", "new instance id remembered")
issecretvalue = function(v) return getmetatable(v) == SECRET end
AW.OnEvent(nil, "UNIT_AURA", "player", { addedAuras = { { name = mk(), spellId = mk(), auraInstanceID = 79 } } })
eq(AW.OnAura({ addedAuras = { { name = mk(), spellId = mk() } }, removedAuraInstanceIDs = { 5 } }), true, "secret aura fields never raise errors")
issecretvalue = nil
_COMBAT = false
C_Spell, C_UnitAuras, C_Secrets = nil, nil, nil

-- cast confirmation with a hidden spell id (combat): the clicked slice decides
AW.buffCache, AW.pendingCast = { ["Aspect of the Hawk"] = true, ["Aspect of the Monkey"] = false }, nil
_COMBAT = true
issecretvalue = function(v) return getmetatable(v) == SECRET end
GetSpellInfo = function(id) if issecretvalue(id) then error("secret") end return "Other Spell" end
AW.NoteClick("Aspect of the Monkey")
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", mk())
eq(AW.buffCache["Aspect of the Monkey"], true, "hidden-id cast matched to the clicked spell")
eq(AW.buffCache["Aspect of the Hawk"], false, "the other aspect turned off")
eq(AW.pendingCast, nil, "click consumed")
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", mk())
eq(AW.buffCache["Aspect of the Hawk"], false, "a cast with no recent click changes nothing")
AW.NoteClick("Aspect of the Hawk")
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 99) -- readable, different spell: not ours
eq(AW.buffCache["Aspect of the Hawk"], false, "a readable cast of another spell does not confirm the click")
AW.pendingCast = nil
_COMBAT, issecretvalue = false, nil
GetSpellInfo = function(id) return "Aimed Shot" end
local rep = AW.BuffReport()
eq(type(rep[1]), "string", "buff report lists slots")

-- #showtooltip
GetSpellInfo = function(n) if n == "Aimed Shot" or n == "Hunter's Mark" then return n end end
local function mt(text) return AW.MacroTooltipSlot(text) end
eq(mt("#showtooltip Aimed Shot\n/cast Aimed Shot").spell, "Aimed Shot", "#showtooltip Spell")
eq(mt("/showtooltip Aimed Shot").spell, "Aimed Shot", "/showtooltip Spell")
eq(mt("#showtooltip\n/cast [@focus] Hunter's Mark").spell, "Hunter's Mark", "bare #showtooltip uses the first /cast")
eq(mt("#showtooltip [mod:shift] Hunter's Mark; Aimed Shot").spell, "Aimed Shot", "fallback picks the default clause")
eq(mt("#showtooltip Hearthstone").item, "Hearthstone", "a non-spell is an item")
eq(mt("#showtooltip !Aimed Shot (Rank 3)").spell, "Aimed Shot", "!, ranks stripped")
eq(mt("/cast Aimed Shot"), nil, "no directive: nothing")
eq(mt("#showtooltip\n/petattack"), nil, "bare directive with no cast")
eq(mt("#showtooltip 13"), nil, "slot numbers unsupported")
SecureCmdOptionParse = function(arg) if string.find(arg, "mod:shift") then return "Hunter's Mark" end return "Aimed Shot" end
eq(mt("#showtooltip [mod:shift] Hunter's Mark; Aimed Shot").spell, "Hunter's Mark", "game parser evaluates conditionals")
SecureCmdOptionParse = function() return nil end
eq(mt("#showtooltip [combat] Aimed Shot"), nil, "no option matches: nothing")
SecureCmdOptionParse = nil
GetSpellTexture = function(n) return "Interface\\Icons\\Spell_" .. n end
eq(AW.SlotIcon({ type = "macro", macrotext = "#showtooltip Aimed Shot\n/cast Aimed Shot", icon = 134400 }), "Interface\\Icons\\Spell_Aimed Shot", "macro icon follows #showtooltip")
eq(AW.SlotIcon({ type = "macro", macrotext = "/cast Aimed Shot", icon = 134400 }), 134400, "macro without it keeps its own icon")
GetSpellCooldown = function() return 100, 10, 1 end
AW.Slash("reset")
AW.P().wheels.main.items[1] = { type = "macro", macrotext = "#showtooltip Aimed Shot\n/cast Aimed Shot" }
AW.ApplyLayout()
_G.ActionWheelsPage1:Show()
eq(pcall(AW.RefreshStates), true, "refresh handles #showtooltip macro slots")
eq(_G.ActionWheelsP1S1.cdStart, 100, "the macro slice shows the cooldown of the spell it points at")

-- icons follow the live spell
AW.spellIdCache = {}
C_Spell = {
	GetSpellInfo = function(n) if n == "Base Spell" then return { spellID = 100 } end end,
	GetOverrideSpell = function(id) if id == 100 then return 200 end return id end,
	GetSpellTexture = function(id) return "tex" .. tostring(id) end,
}
eq(AW.SlotIcon({ type = "spell", spell = "Base Spell" }), "tex200", "override spell icon wins")
C_Spell.GetOverrideSpell = function(id) return id end
eq(AW.SlotIcon({ type = "spell", spell = "Base Spell" }), "texBase Spell", "no override: the spell's own icon")
C_Spell = nil
eq(AW.SlotIcon({ type = "spell", spell = "X", icon = "mine" }), "mine", "a chosen icon is kept")
-- the slice re-reads its icon on refresh
local cur = "iconA"
GetSpellTexture = function() return cur end
AW.Slash("reset")
AW.Slash("set 1 spell Changer")
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.iconTex, "iconA", "slice shows the spell icon")
cur = "iconB"
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.iconTex, "iconB", "slice follows the spell when its icon changes")

-- mirror the action bar's icon and checked state
AW.actionSlots, AW.spellIdCache = {}, {}
C_Spell = { GetSpellInfo = function(n) if n == "Aspect of the Hawk" then return { spellID = 13165 } end end }
C_ActionBar = {
	FindSpellActionButtons = function(id) if id == 13165 then return { 7 } end return {} end,
	GetActionTexture = function(slot) return slot == 7 and "barIcon" or nil end,
	IsCurrentAction = function(slot) return slot == 7 end,
}
local tex, chk = AW.ActionBarLook("Aspect of the Hawk")
eq(tex, "barIcon", "action bar icon mirrored"); eq(chk, true, "action bar checked state mirrored")
eq(AW.SlotIcon({ type = "spell", spell = "Aspect of the Hawk" }), "barIcon", "slot icon is the action bar's icon")
eq(AW.SlotState({ type = "spell", spell = "Aspect of the Hawk" }).active, true, "checked on the bar means active")
eq(AW.ActionBarLook("Not On A Bar"), nil, "spells not on a bar have no bar look")
-- classic-style scan
C_ActionBar = nil
GetActionInfo = function(i) if i == 12 then return "spell", 13165 end return nil end
GetActionTexture = function(slot) return slot == 12 and "scanIcon" or nil end
IsCurrentAction = function(slot) return false end
AW.actionSlots = {}
eq((AW.ActionBarLook("Aspect of the Hawk")), "scanIcon", "found by scanning the slots")
-- bars change: cache cleared by the event
AW.OnEvent(nil, "ACTIONBAR_SLOT_CHANGED")
eq(next(AW.actionSlots), nil, "slot cache cleared when the bars change")
-- secret values from the bar are ignored
issecretvalue = function(v) return getmetatable(v) == SECRET end
GetActionTexture = function() return mk() end
IsCurrentAction = function() return mk() end
AW.actionSlots = {}
local st2, ck2 = AW.ActionBarLook("Aspect of the Hawk")
eq(st2, nil, "secret bar icon ignored"); eq(ck2, nil, "secret checked state ignored")
issecretvalue, GetActionInfo, GetActionTexture, IsCurrentAction = nil, nil, nil, nil
C_Spell = nil
AW.actionSlots, AW.spellIdCache = {}, {}

-- /aw inspect
C_Spell = { GetSpellInfo = function(n) return { spellID = 1, iconID = 111, originalIconID = 222 } end, GetSpellTexture = function(id) return 333 end }
local insp = AW.InspectSpell("Aspect of the Hawk")
local joined = table.concat(insp, "\n")
eq(string.find(joined, "iconID, originalIconID: 111, 222", 1, true) ~= nil, true, "inspect shows iconID and originalIconID")
eq(string.find(joined, "GetSpellTexture(name): 333", 1, true) ~= nil, true, "inspect shows the texture lookups")
AW.Slash("inspect Aspect of the Hawk")
C_Spell = nil

-- learning the icon a spell shows while active
ActionWheelsDB.activeIcons = nil
AW.actionSlots, AW.spellIdCache, AW.buffCache = {}, {}, {}
local barTex, active = 136076, false
C_Spell = { GetSpellInfo = function(n) return { spellID = 14319 } end, GetSpellTexture = function() return 136076 end }
C_ActionBar = {
	FindSpellActionButtons = function() return { 70 } end,
	GetActionTexture = function() return barTex end,
	IsCurrentAction = function() return false end,
}
C_UnitAuras = { GetPlayerAuraBySpellID = function() if active then return { auraInstanceID = 5, icon = 136116 } end end }
local hawk = { type = "spell", spell = "Aspect of the Hawk" }
AW.SlotState(hawk)
eq(AW.ActiveIcon("Aspect of the Hawk"), 136116, "an Aspect has the built-in active icon before anything is learned")
eq(AW.ActiveIcon("Aimed Shot"), nil, "other spells have none")
eq(ActionWheelsDB.activeIcons, nil, "nothing learned while inactive")
active, barTex = true, 777
AW.SlotState(hawk)
eq(AW.ActiveIcon("Aspect of the Hawk"), 777, "active icon learned")
eq(ActionWheelsDB.activeIcons["Aspect of the Hawk"].bar, 777, "learned from the bar")
eq(AW.ActiveIcon("Aspect of the Monkey"), 777, "what one Aspect shows, all Aspects show")
eq(ActionWheelsDB.activeIcons["Aspect of the Hawk"].aura, 136116, "and from the buff")
ActionWheelsDB.activeIcons["Aspect of the Monkey"] = { bar = 555 }
eq(AW.ActiveIcon("Aspect of the Monkey"), 555, "an Aspect's own learned icon beats the shared one")
ActionWheelsDB.activeIcons["Aspect of the Monkey"] = nil
-- the wheel shows it, even for a spell on no bar and in combat
C_ActionBar, barTex = nil, 136076
AW.actionSlots = {}
GetActionInfo = nil
_COMBAT = true
C_UnitAuras = nil
AW.buffCache["Aspect of the Hawk"] = true
AW.Slash("reset")
AW.P().wheels.main.items[1] = { type = "spell", spell = "Aspect of the Hawk" }
AW.ApplyLayout()
_COMBAT = true
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.iconTex, 777, "active spell shows the learned icon in combat with no bar")
AW.buffCache["Aspect of the Hawk"] = false
AW.RefreshStates()
eq(_G.ActionWheelsP1S1.iconTex, 136076, "back to the normal icon when it is not active")
_COMBAT = false
-- never learn the normal icon, never in combat
ActionWheelsDB.activeIcons = nil
barTex = 136076
C_ActionBar = { FindSpellActionButtons = function() return { 70 } end, GetActionTexture = function() return barTex end }
AW.actionSlots = {}
AW.buffCache["Aspect of the Hawk"] = true
AW.LearnActiveIcon("Aspect of the Hawk")
eq(ActionWheelsDB.activeIcons, nil, "the normal icon is not learned")
C_Spell, C_ActionBar, C_UnitAuras = nil, nil, nil
GetSpellTexture = function() return "x" end
AW.actionSlots, AW.spellIdCache = {}, {}

-- close behaviour after a click
eq(AW.SecureAttributes({ type = "spell", spell = "X" }, nil, "success").macrotext, "/cast X", "success mode: a spell slice has no close line")
eq(AW.SecureAttributes({ type = "spell", spell = "X" }, nil, "click").macrotext, "/cast X\n/click ActionWheelsClose", "click mode: closes right away")
eq(AW.SecureAttributes({ type = "spell", spell = "X" }, nil, "never").macrotext, "/cast X", "never mode: no close line")
eq(AW.SecureAttributes({ type = "item", item = "Y" }, nil, "success").macrotext, "/use Y\n/click ActionWheelsClose", "success mode: items still close on click")
eq(AW.SecureAttributes({ type = "pet", pet = "attack" }, nil, "success").macrotext, "/petattack\n/click ActionWheelsClose", "success mode: pet commands still close on click")
eq(AW.SecureAttributes({ type = "macro", macrotext = "/z" }, nil, "never").macrotext, "/z", "never mode: macros keep no close line")
eq(AW.SecureAttributes({ type = "spell", spell = "X" }, "2", "never").macrotext, "/click ActionWheelsGo2", "sub-wheel slices are unaffected")
AW.Slash("reset")
eq(AW.P().settings.closeMode, "success", "default close mode")
AW.Slash("close click")
eq(AW.P().settings.closeMode, "click", "/aw close click")
AW.Slash("close sideways")
eq(AW.P().settings.closeMode, "click", "bad close mode rejected")
AW.P().wheels.main.items[1] = { type = "spell", spell = "Aimed Shot" }
AW.ApplyLayout()
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/cast Aimed Shot\n/click ActionWheelsClose", "layout follows the close mode")
AW.Slash("close success")
eq(_G.ActionWheelsP1S1:GetAttribute("macrotext"), "/cast Aimed Shot", "and changes with it")
ActionWheelsDB.profile.settings.closeMode = "bogus"
AW.InitDB()
eq(AW.P().settings.closeMode, "success", "a bad saved close mode is repaired")

-- click feedback and closing on a confirmed cast
local sl = _G.ActionWheelsP1S1
sl.flash = sl.flash or {}
GetSpellInfo = function(id) return "Aimed Shot" end
_COMBAT = false
AW.closeWatch = { name = "Aimed Shot", t = 1000, slice = sl }
_G.ActionWheelsRoot:Show()
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 19434)
eq(AW.closeWatch, nil, "a matching cast clears the watch")
eq(_G.ActionWheelsRoot:IsShown(), false, "the wheel closes when the cast is confirmed out of combat")
eq(AW.flashing[sl], true, "the slice flashes on success")
AW.closeWatch = { name = "Multi-Shot", t = 1000, slice = sl }
_G.ActionWheelsRoot:Show()
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 19434) -- Aimed Shot, not ours
eq(_G.ActionWheelsRoot:IsShown(), true, "another spell's cast does not close the wheel")
_COMBAT = true
AW.closeWatch = { name = "Aimed Shot", t = 1000, slice = sl }
AW.OnEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", 19434)
eq(_G.ActionWheelsRoot:IsShown(), true, "in combat the wheel stays open (it can't be hidden from Lua)")
eq(AW.closeWatch, nil, "but the confirmation is still noticed")
_COMBAT = false
_G.ActionWheelsRoot:Hide()
AW.flashing = {}
AW.FlashSlice(sl, 1, 1, 1)
eq(AW.flashing[sl], true, "flash starts")
AW.AnimateFlashes()
eq(AW.flashing[sl], true, "flash still running right away")

-- a failing cooldown / count display must not leave a stale highlight
AW.Slash("reset")
AW.P().wheels.main.items[1] = { type = "spell", spell = "Aspect of the Hawk" }
AW.P().wheels.main.items[2] = { type = "spell", spell = "Aspect of the Monkey" }
AW.ApplyLayout()
AW.buffCache = { ["Aspect of the Hawk"] = false, ["Aspect of the Monkey"] = true }
local s1, s2 = _G.ActionWheelsP1S1, _G.ActionWheelsP1S2
s1.cd.SetCooldown = function() error("secret value refused") end
s2.cd.SetCooldown = function() error("secret value refused") end
s1.count.SetText = function() error("secret value refused") end
local origRing = s1.ring.SetVertexColor
s1.glow:Show(); s1.ring.SetVertexColor = function(_, r, g) s1.ringR = r end
_COMBAT = true
GetSpellCooldown = function() return 100, 10, 1 end
GetSpellCharges = nil
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(s1.glow:IsShown(), false, "the Hawk slice loses its highlight even if its cooldown display fails")
eq(s2.glow:IsShown(), true, "the active slice gets its highlight even if its cooldown display fails")
eq(s1.ringR, 0.4, "the ring is reset on the inactive slice")
AW.debug = true
AW.RefreshStates()
AW.debug = false
_COMBAT = false
s1.cd.SetCooldown, s2.cd.SetCooldown, s1.count.SetText = nil, nil, nil
s1.ring.SetVertexColor = origRing

-- auto key behaviour: hold in combat, toggle out of combat
eq(_STATEDRV.combatmode, "[combat] hold; toggle", "combat state driver registered")
eq(_G.ActionWheelsRoot:GetAttribute("combatmode"), "toggle", "starts in toggle")
eq(type(_G.ActionWheelsRoot:GetAttribute("_onstate-combatmode")), "string", "state handler installed")
AW.Slash("mode auto")
eq(AW.P().settings.openMode, "auto", "auto mode accepted")
eq(_G.ActionWheelsToggle:GetAttribute("mode"), "auto", "toggle button gets auto")
eq(string.find(_G.ActionWheelsToggle:GetAttribute("_onclick"), 'combatmode', 1, true) ~= nil, true, "click snippet reads the combat state")
AW.Slash("mode sideways")
eq(AW.P().settings.openMode, "auto", "bad mode rejected")
ActionWheelsDB.profile.settings.openMode = "bogus"
AW.InitDB()
eq(AW.P().settings.openMode, "toggle", "a bad saved mode is repaired")
AW.Slash("mode toggle")

-- mouse openers
eq(_G.ActionWheelsOpen ~= nil, true, "macro opener exists")
eq(_G.ActionWheelsOpen2:GetAttribute("target"), "page2", "numbered opener targets that wheel")
eq(_G.ActionWheelsOpen:GetAttribute("target"), nil, "plain opener opens the first wheel")
eq(_G.ActionWheelsLauncher ~= nil, true, "launcher exists")
eq(type(_G.ActionWheelsOpen:GetAttribute("_onclick")), "string", "opener has a click handler")
eq(_G.ActionWheelsOpen:GetAttribute("at"), "center", "action bar macros open at the screen centre by default")
eq(_G.ActionWheelsOpen2:GetAttribute("at"), "center", "including the numbered ones")
eq(_G.ActionWheelsLauncher:GetAttribute("at"), "cursor", "the on-screen button follows the open position setting")
AW.Slash("at center")
eq(_G.ActionWheelsLauncher:GetAttribute("at"), "center", "launcher follows 'opens at'")
eq(_G.ActionWheelsOpen:GetAttribute("at"), "center", "action bar macros stay central")
AW.Slash("at cursor")
AW.Slash("barat cursor")
eq(_G.ActionWheelsOpen:GetAttribute("at"), "cursor", "/aw barat cursor")
eq(_G.ActionWheelsLauncher1:GetAttribute("at"), "cursor", "launchers unaffected by barat")
AW.Slash("barat sideways")
eq(AW.P().settings.barOpenAt, "cursor", "bad value rejected")
AW.Slash("barat center")
ActionWheelsDB.profile.settings.barOpenAt = "bogus"
AW.InitDB()
eq(AW.P().settings.barOpenAt, "center", "bad saved value repaired")
AW.Slash("launcher")
eq(ActionWheelsDB.launcher.hide, false, "/aw launcher shows the button")
eq(_G.ActionWheelsLauncher:IsShown(), true, "the launcher is visible")
AW.Slash("launcher lock")
eq(ActionWheelsDB.launcher.locked, true, "lock")
AW.Slash("launcher unlock")
eq(ActionWheelsDB.launcher.locked, false, "unlock")
ActionWheelsDB.launcher.x, ActionWheelsDB.launcher.y = 300, 200
AW.Slash("launcher reset")
eq(ActionWheelsDB.launcher.x, nil, "reset forgets the position")
AW.Slash("launcher")
eq(_G.ActionWheelsLauncher:IsShown(), false, "toggled off again")
_COMBAT = true
AW.Slash("launcher")
eq(AW.pendingApply, true, "in combat the launcher change waits")
_COMBAT = false
AW.OnEvent(nil, "PLAYER_REGEN_ENABLED")
eq(_G.ActionWheelsLauncher:IsShown(), true, "and applies after combat")
AW.Slash("launcher")

-- last wheel, per-wheel buttons, action bar macros
AW.Slash("reset")
eq(_G.ActionWheelsLauncher:GetAttribute("target"), "last", "the on-screen button opens the last wheel used")
eq(_G.ActionWheelsOpenLast:GetAttribute("target"), "last", "last-wheel macro opener exists")
eq(string.find(_G.ActionWheelsOpen:GetAttribute("_onclick"), 'target == "last"', 1, true) ~= nil, true, "opener snippet understands 'last'")
eq(string.find(_G.ActionWheelsRoot:GetAttribute("gopage"), 'SetAttribute("last"', 1, true) ~= nil, true, "switching pages records the last wheel")
eq(_G.ActionWheelsLauncher2:GetAttribute("target"), "page2", "per-wheel button targets its wheel")
AW.Slash("wheel new Second")
AW.Slash("wheel select 1")
AW.Slash("launcher wheel")
eq(AW.P().wheels.main.launcher.show, true, "wheel 1 gets its own button")
eq(_G.ActionWheelsLauncher1:IsShown(), true, "its button is visible")
eq(_G.ActionWheelsLauncher2:IsShown(), false, "wheel 2 has none yet")
AW.Slash("wheel select 2")
AW.Slash("launcher wheel")
eq(_G.ActionWheelsLauncher2:IsShown(), true, "wheel 2's button appears")
-- positions are per wheel
local d1 = AW.LauncherData(_G.ActionWheelsLauncher1, true)
d1.x, d1.y = 111, 222
local d2 = AW.LauncherData(_G.ActionWheelsLauncher2, true)
eq(d2.x, nil, "each wheel keeps its own position")
AW.PlaceLaunchers()
AW.Slash("launcher reset")
eq(AW.P().wheels.main.launcher.x, nil, "reset clears every button's position")
eq(AW.P().wheels.main.launcher.show, true, "but keeps them visible")
-- deleting a wheel removes its button
AW.Slash("wheel delete")
eq(_G.ActionWheelsLauncher2:IsShown(), false, "a deleted wheel's button goes away")
-- exports never carry buttons
local ex = AW.PreviewImport(AW.ExportWheels({ "main" }))
eq(ex.wheels[1].launcher, nil, "launcher buttons are not exported")
-- macros
eq(select(2, AW.OpenMacroFor("last")), "/click ActionWheelsOpenLast", "macro for the last wheel")
eq(select(2, AW.OpenMacroFor("first")), "/click ActionWheelsOpen", "macro for the first wheel")
eq(select(2, AW.OpenMacroFor("main")), "/click ActionWheelsOpen1", "macro for a specific wheel")
eq(AW.OpenMacroFor("nope"), nil, "no macro for an unknown wheel")
local made, picked, edited = {}, nil, nil
GetMacroIndexByName = function(n) return made[n] or 0 end
CreateMacro = function(n, icon, body, isLocal) made[n] = 5; made.body = body; return 5 end
EditMacro = function(i, n, icon, body) edited = body end
PickupMacro = function(i) picked = i end
eq(AW.MakeActionBarMacro("last"), true, "macro created")
eq(made.body, "/click ActionWheelsOpenLast", "with the right body")
eq(picked, 5, "and put on the cursor")
picked = nil
eq(AW.MakeActionBarMacro("last"), true, "second time updates the existing macro")
eq(edited, "/click ActionWheelsOpenLast", "edited, not duplicated")
_COMBAT = true
eq(AW.MakeActionBarMacro("last"), false, "no macro making in combat")
_COMBAT = false
CreateMacro = function() return nil end
eq(AW.MakeActionBarMacro("first"), false, "a full macro list is reported, not an error")
GetMacroIndexByName, CreateMacro, EditMacro, PickupMacro = nil, nil, nil, nil
eq(AW.MakeActionBarMacro("first"), false, "no macro API: the line is printed instead")
AW.Slash("macro first")

-- key opens last wheel, mouse wheel paging
AW.Slash("reset")
eq(AW.P().settings.openFirst, "last", "default: the key opens the last wheel used")
eq(_G.ActionWheelsToggle:GetAttribute("first"), "last", "toggle button knows")
AW.Slash("opens selected")
eq(_G.ActionWheelsToggle:GetAttribute("first"), "selected", "the old behaviour is a setting")
AW.Slash("opens last")
eq(AW.P().settings.openFirst, "last", "/aw opens last")
eq(_G.ActionWheelsToggle:GetAttribute("first"), "last", "toggle button follows the setting")
eq(string.find(_G.ActionWheelsToggle:GetAttribute("_onclick"), 'defhome', 1, true) ~= nil, true, "auto conditions still win over 'last'")
AW.Slash("opens sideways")
eq(AW.P().settings.openFirst, "last", "bad value rejected")
ActionWheelsDB.profile.settings.openFirst = "bogus"
AW.InitDB()
eq(AW.P().settings.openFirst, "last", "bad saved value repaired")
eq(_G.ActionWheelsRoot:GetAttribute("defhome"), "page1", "the default first wheel is recorded")
eq(_G.ActionWheelsRoot:GetAttribute("wheelscroll"), 1, "mouse wheel paging on by default")
eq(_G.ActionWheelsRoot:GetAttribute("wheelrev"), 0, "not reversed by default")
eq(type(_G.ActionWheelsCatcher:GetAttribute("_onmousewheel")), "string", "catcher handles the mouse wheel")
AW.Slash("scroll off")
eq(_G.ActionWheelsRoot:GetAttribute("wheelscroll"), 0, "mouse wheel paging off")
AW.Slash("scroll on")
AW.Slash("scroll reverse")
eq(_G.ActionWheelsRoot:GetAttribute("wheelrev"), 1, "reversed")
AW.Slash("scroll reverse")
eq(_G.ActionWheelsRoot:GetAttribute("wheelrev"), 0, "back to normal")

-- ===== ReactWheel-inspired additions =====
AW.Slash("reset")
-- colours
eq(AW.SlotColor({ color = "green" }), 0.3, "slot colour lookup")
eq(AW.SlotColor({ color = "mauve" }), nil, "unknown colour ignored")
eq(AW.SlotColor(nil), nil, "no slot, no colour")
local cimp = AW.PreviewImport(AW.Serialize({ v = 1, wheels = { { name = "C", slots = 4, items = { { type = "pet", pet = "attack", color = "red" }, { type = "pet", pet = "follow", color = "evil" } } } } }))
eq(cimp.wheels[1].items[1].color, "red", "a known colour is imported")
eq(cimp.wheels[1].items[2].color, nil, "an unknown colour is dropped")
AW.P().wheels.main.items[1].color = "gold"
AW.ApplyLayout()
eq(_G.ActionWheelsP1S1.baseRing[1], 1, "slice border follows the slot colour (r)")
eq(_G.ActionWheelsP1S1.baseRing[3], 0.1, "slice border follows the slot colour (b)")
eq(_G.ActionWheelsP1S2.baseRing[1], 0.4, "uncoloured slots keep the default border")
-- reorder / copy wheels
AW.Slash("wheel new Two")
AW.Slash("wheel new Three")
local p = AW.P()
eq(p.order[3], "w3", "order before move")
AW.Slash("wheel move up")
eq(p.order[2], "w3", "wheel moved up")
eq(p.order[3], "w2", "its neighbour moved down")
AW.Slash("wheel move up")
AW.Slash("wheel move up")
eq(p.order[1], "w3", "moved to the top")
AW.Slash("wheel move up")
eq(p.order[1], "w3", "can't move past the top")
eq(_G.ActionWheelsPage1:GetAttribute("next"), "page2", "paging follows the new order")
AW.Slash("wheel select main")
AW.Slash("wheel copy")
eq(#p.order, 4, "wheel copied")
eq(p.wheels[p.current].name, "Main copy", "copy is named and selected")
eq(p.wheels[p.current].items[1].pet, "attack", "copy has the slots")
eq(p.wheels[p.current].items[1] ~= p.wheels.main.items[1], true, "and they are independent tables")
for _ = 1, 8 do AW.Slash("wheel copy") end
eq(#p.order, AW.MAXWHEELS, "copies stop at the wheel limit")
AW.Slash("reset")
p = AW.P()
-- swap slots
AW.P().wheels.main.items[1] = { type = "spell", spell = "A" }
AW.P().wheels.main.items[2] = { type = "spell", spell = "B" }
AW.Slash("swap 1 2")
eq(AW.P().wheels.main.items[1].spell, "B", "slots swapped"); eq(AW.P().wheels.main.items[2].spell, "A", "both ways")
AW.Slash("swap 1 1")
eq(AW.P().wheels.main.items[1].spell, "B", "swapping a slot with itself does nothing")
AW.Slash("swap 1 99")
eq(AW.P().wheels.main.items[1].spell, "B", "out-of-range swap rejected")
-- swap mode from the wheel menu
AW.P().wheels.main.items[3] = nil
AW.ApplyLayout()
local s1, s2 = _G.ActionWheelsP1S1, _G.ActionWheelsP1S2
s1.page.wheelId = "main"
AW.BeginSwap(s1)
eq(AW.swap ~= nil, true, "swap mode on")
eq(s2:GetAttribute("macrotext"), nil, "slices are inert in swap mode")
AW.FinishSwap(s2)
eq(AW.swap, nil, "swap mode off")
eq(AW.P().wheels.main.items[1].spell, "A", "swapped through the wheel")
eq(s1:GetAttribute("macrotext") ~= nil, true, "slices work again afterwards")
AW.BeginSwap(s1); AW.CancelSwap()
eq(AW.swap, nil, "cancel leaves everything as it was")
-- menu builds, and refuses in combat
AW.ShowSlotMenu(s1)
_COMBAT = true
AW.ShowSlotMenu(s1)
_COMBAT = false
AW.HideSlotMenu()
-- edit-slot from the wheel opens the editor on that slot
AW.HideConfig()
AW.EditSlot("main", 2)
eq(AW.ConfigShown(), true, "Edit slot opens the editor")
AW.HideConfig()
-- open from a command
local clicked
AW.Slash("wheel new Extra")
_G.ActionWheelsOpen2.Click = function(self, b, d) clicked = "2" end
_G.ActionWheelsOpenLast.Click = function(self, b, d) clicked = "last" end
_G.ActionWheelsOpen.Click = function(self, b, d) clicked = "first" end
AW.Slash("open 2"); eq(clicked, "2", "/aw open <number>")
AW.Slash("open Extra"); eq(clicked, "2", "/aw open <name>")
AW.Slash("open last"); eq(clicked, "last", "/aw open last")
AW.Slash("open"); eq(clicked, "first", "/aw open")
clicked = nil
_COMBAT = true
AW.Slash("open 2"); eq(clicked, nil, "no opening by command in combat")
_COMBAT = false
AW.Slash("open nowhere"); eq(clicked, nil, "unknown wheel")
-- sounds
local played = 0
PlaySound = function() played = played + 1 end
AW.Sound("hover"); eq(played, 0, "sounds are off by default")
AW.Slash("sounds")
AW.Sound("hover"); AW.Sound("use")
eq(played, 2, "sounds play when on")
AW.Slash("sounds"); PlaySound = nil
-- sizes
ActionWheelsDB.profile.settings.fontScale, ActionWheelsDB.profile.settings.hubScale = 9, 0
AW.InitDB()
eq(AW.P().settings.fontScale, 2.5, "text size clamped"); eq(AW.P().settings.hubScale, 0.8, "centre size clamped")
AW.P().settings.hubScale, AW.P().settings.fontScale = 2, 1.5
eq(pcall(AW.ApplyLayout), true, "layout copes with larger text and centre sizes")
AW.Slash("reset")

-- secret cooldowns use the game's duration object
AW.spellIdCache = {}
local SECRET2 = {}
local function mk2() return setmetatable({}, SECRET2) end
issecretvalue = function(v) return getmetatable(v) == SECRET2 end
local durObj = { "duration object" }
C_Spell = {
	GetSpellInfo = function() return { spellID = 77 } end,
	GetSpellCooldown = function() return { startTime = mk2(), duration = mk2(), isOnGCD = false } end,
	GetSpellCooldownDuration = function(id) if id == 77 then return durObj end end,
}
local sd = AW.SlotState({ type = "spell", spell = "Aimed Shot" })
eq(sd.cdSecret, true, "secret cooldown"); eq(sd.cdObject, durObj, "duration object fetched for it")
local usedObj
AW.Slash("reset")
AW.P().wheels.main.items[1] = { type = "spell", spell = "Aimed Shot" }
AW.ApplyLayout()
local sl1 = _G.ActionWheelsP1S1
sl1.cd.SetCooldownFromDurationObject = function(_, o, clear) usedObj = o; sl1.clearArg = clear end
_COMBAT = true
_G.ActionWheelsPage1:Show()
AW.RefreshStates()
eq(usedObj, durObj, "the swirl is driven from the duration object in combat")
eq(sl1.clearArg, true, "and clears when the cooldown is over")
_COMBAT = false
sl1.cd.SetCooldownFromDurationObject = nil
C_Spell, issecretvalue = nil, nil
AW.spellIdCache = {}

-- ===== cooldown strip =====
local savedCooldownStub = GetSpellCooldown
AW.Slash("reset")
local tr = ActionWheelsDB.tracker
eq(tr.auto, true, "automatic tracking on by default"); eq(tr.threshold, 30, "30 s counts as long"); eq(tr.locked, true, "locked by default")
AW.spellIdCache = {}
C_Spell = { GetSpellInfo = function(n) return { spellID = ({ ["Trueshot"] = 1, ["Aimed Shot"] = 2, ["Kill Command"] = 3 })[n] } end }
GetSpellBaseCooldown = function(id) return ({ [1] = 180000, [2] = 10000, [3] = 45000 })[id] or 0, 1500 end
AW.P().wheels.main.items[1] = { type = "spell", spell = "Trueshot" }
AW.P().wheels.main.items[2] = { type = "spell", spell = "Aimed Shot" }
AW.P().wheels.main.items[3] = { type = "spell", spell = "Kill Command", track = true }
AW.P().wheels.main.items[4] = { type = "macro", macrotext = "#showtooltip Trueshot\n/cast Trueshot" }
local list = AW.TrackerCollect()
local names = {}
for _, e in ipairs(list) do names[e.name] = e end
eq(names["Trueshot"] ~= nil, true, "a long-cooldown spell is picked up automatically")
eq(names["Aimed Shot"], nil, "a short one is not")
eq(names["Kill Command"].manual, true, "a ticked spell is always tracked")
eq(#list, 2, "a macro pointing at an already tracked spell adds no duplicate")
tr.auto = false
list = AW.TrackerCollect()
eq(#list, 1, "with automatic off only ticked spells remain"); eq(list[1].name, "Kill Command", "the ticked one")
tr.auto = true; tr.threshold = 60
list = AW.TrackerCollect()
eq(#list, 2, "threshold 60: Trueshot (180) and the ticked Kill Command"); tr.threshold = 200
list = AW.TrackerCollect()
eq(#list, 1, "threshold 200: only the ticked one"); tr.threshold = 30
-- learned cooldown lengths when the game gives no base cooldown
GetSpellBaseCooldown = nil
tr.learned = { Trueshot = 180 }
eq(AW.TrackerBaseCooldown("Trueshot"), 180, "learned length used when the game does not say")
eq(AW.TrackerBaseCooldown("Unknown"), 0, "unknown spells have none")
tr.learned = {}
-- visibility and ready transitions
local manual = { name = "M", manual = true }
local auto = { name = "A", manual = false }
eq(AW.TrackerVisible(manual, false, 100), true, "manual entries are always visible")
eq(AW.TrackerVisible(auto, false, 100), false, "automatic ones hide while ready")
eq(AW.TrackerVisible(auto, true, 100), true, "and show while cooling down")
eq(AW.TrackerVisible(auto, false, 103), true, "and stay visible for a few seconds once ready")
eq(AW.TrackerVisible(auto, false, 120), false, "then disappear")
eq(AW.TrackerTransition(auto, true), false, "starting a cooldown is not 'ready'")
eq(AW.TrackerTransition(auto, true), false, "still running")
eq(AW.TrackerTransition(auto, false), true, "finishing is 'ready' exactly once")
eq(AW.TrackerTransition(auto, false), false, "and not again")
-- the strip builds and updates; flashes on ready
GetSpellBaseCooldown = function(id) return ({ [1] = 180000, [2] = 10000, [3] = 45000 })[id] or 0, 1500 end
AW.TrackerRefresh()
local running = true
GetSpellCooldown = function() if running then return 100, 180, 1 end return 0, 0, 0 end
AW.spellIdCache = {}
AW.TrackerRefresh()
AW.TrackerUpdate()
eq(_G.ActionWheelsTrackerIcon1 ~= nil, true, "icons are created on demand")
eq(_G.ActionWheelsTrackerIcon1:IsShown(), true, "a cooling spell is shown")
eq(tr.learned["Trueshot"], 180, "a long cooldown seen out of combat is remembered")
running = false
AW.TrackerUpdate()
eq(_G.ActionWheelsTrackerIcon1.flashT ~= nil, true, "the icon flashes when the spell is ready")
tr.flash = false
-- settings sanitising and slash
tr.threshold, tr.size, tr.dir = 9999, 1, "sideways"
AW.InitDB()
eq(tr.threshold, 600, "threshold clamped"); eq(tr.size, 20, "size clamped"); eq(tr.dir, "right", "bad direction repaired")
AW.Slash("tracker")
eq(ActionWheelsDB.tracker.hide, true, "/aw tracker hides")
AW.Slash("tracker")
AW.Slash("tracker unlock")
eq(ActionWheelsDB.tracker.locked, false, "unlock")
AW.Slash("tracker lock")
eq(ActionWheelsDB.tracker.locked, true, "lock")
ActionWheelsDB.tracker.x, ActionWheelsDB.tracker.y = 50, 60
AW.Slash("tracker reset")
eq(ActionWheelsDB.tracker.x, nil, "reset forgets the position")
-- import keeps the strip tick on spells only
local timp = AW.PreviewImport(AW.Serialize({ v = 1, wheels = { { name = "T", slots = 4, items = { { type = "spell", spell = "X", track = true }, { type = "pet", pet = "attack", track = true } } } } }))
eq(timp.wheels[1].items[1].track, true, "the strip tick survives an import for spells")
eq(timp.wheels[1].items[2].track, nil, "but not for other slot types")
GetSpellBaseCooldown, GetSpellCooldown, C_Spell = nil, savedCooldownStub, nil
AW.spellIdCache = {}
AW.Slash("reset")

-- tooltips
AW.Slash("reset")
AW.spellIdCache = {}
local tipLog = {}
local realTip = GameTooltip
GameTooltip = setmetatable({}, { __index = function(_, k) return function() end end })
GameTooltip.SetOwner = function(self, owner, anchor) tipLog[#tipLog + 1] = "owner" end
GameTooltip.ClearLines = function() tipLog[#tipLog + 1] = "clear" end
GameTooltip.AddLine = function(self, text) tipLog[#tipLog + 1] = "line:" .. tostring(text) end
GameTooltip.Show = function() tipLog[#tipLog + 1] = "show" end
GameTooltip.Hide = function() tipLog[#tipLog + 1] = "hide" end
local setSpell, setItem, lines = nil, nil, 0
GameTooltip.SetSpellByID = function(self, id) setSpell = id; lines = 3 end
GameTooltip.SetItemByID = function(self, id) setItem = id; lines = 3 end
GameTooltip.NumLines = function() return lines end
C_Spell = { GetSpellInfo = function(n) return { spellID = 4242 } end }
GetItemInfoInstant = function() return 6948 end
AW.P().wheels.main.items[1] = { type = "spell", spell = "Aimed Shot" }
AW.P().wheels.main.items[2] = { type = "item", item = "Hearthstone" }
AW.P().wheels.main.items[3] = { type = "macro", macrotext = "#showtooltip Aimed Shot\n/cast Aimed Shot" }
AW.P().wheels.main.items[4] = { type = "macro", macrotext = "/dismount\n/leavevehicle", label = "Dismount" }
AW.P().wheels.main.items[5] = { type = "pet", pet = "attack" }
AW.ApplyLayout()
GetSpellInfo = function(n) return n end
local function hover(i) tipLog = {}; setSpell, setItem, lines = nil, nil, 0; AW.ShowSlotTooltip(_G["ActionWheelsP1S" .. i]) end
hover(1); eq(setSpell, 4242, "a spell slice shows the game's spell tooltip")
hover(2); eq(setItem, 6948, "an item slice shows the game's item tooltip")
setSpell = nil; hover(3); eq(setSpell, 4242, "a #showtooltip macro shows the tooltip of its spell")
hover(4)
eq(table.concat(tipLog, "|"), "owner|clear|line:Dismount|line:/dismount|line:/leavevehicle|show", "a macro lists its lines")
hover(5)
eq(table.concat(tipLog, "|"), "owner|clear|line:Pet: attack|line:Pet command|show", "a pet command is described")
AW.P().wheels.main.items[6] = { type = "wheel", wheel = "w9" } -- dangling link: no crash
AW.ApplyLayout()
hover(6)
AW.P().wheels.main.items[8] = nil
AW.ApplyLayout()
hover(8) -- an empty slot: no tooltip
eq(#tipLog, 0, "empty slots show nothing")
GameTooltip.SetSpellByID = function() error("refused") end
hover(1)
eq(tipLog[#tipLog], "show", "a refused spell tooltip falls back to a description")
AW.Slash("tooltips")
eq(AW.P().settings.tooltips, false, "/aw tooltips turns them off")
hover(1)
eq(#tipLog, 0, "no tooltip when off")
AW.Slash("tooltips")
GameTooltip, C_Spell, GetSpellInfo, GetItemInfoInstant = realTip, nil, nil, nil
AW.spellIdCache = {}
AW.Slash("reset")

-- dragging the cooldown strip
local shiftDown = false
IsShiftKeyDown = function() return shiftDown end
local moved, stopped = 0, 0
local trf = _G.ActionWheelsTracker
trf.StartMoving = function() moved = moved + 1 end
trf.StopMovingOrSizing = function() stopped = stopped + 1 end
trf.GetLeft = function() return 120 end
trf.GetTop = function() return 340 end
ActionWheelsDB.tracker.locked = true
eq(AW.TrackerDragStart(), false, "a locked strip does not move on a plain drag")
shiftDown = true
eq(AW.TrackerDragStart(), true, "Shift + drag moves it even when locked")
eq(moved, 1, "StartMoving was called")
AW.TrackerDragStop()
eq(ActionWheelsDB.tracker.x, 120, "the position is saved (x)"); eq(ActionWheelsDB.tracker.y, 340, "the position is saved (y)")
shiftDown = false
ActionWheelsDB.tracker.locked = false
eq(AW.TrackerDragStart(), true, "a plain drag works while unlocked")
AW.TrackerDragStop()
eq(stopped, 2, "StopMovingOrSizing after each drag")
AW.TrackerDragStop()
eq(stopped, 2, "a stop without a start does nothing")
ActionWheelsDB.tracker.locked = true
ActionWheelsDB.tracker.x, ActionWheelsDB.tracker.y = nil, nil
IsShiftKeyDown = nil
trf.StartMoving, trf.StopMovingOrSizing, trf.GetLeft, trf.GetTop = nil, nil, nil, nil

-- last wheel survives sessions; mouse wheel does not wrap
AW.Slash("reset")
AW.Slash("wheel new Two")
AW.Slash("wheel new Three")
AW.Slash("wheel select 1")
eq(_G.ActionWheelsPage1:GetAttribute("idx"), 1, "pages know their position"); eq(_G.ActionWheelsPage3:GetAttribute("idx"), 3, "page 3 is third")
eq(_G.ActionWheelsRoot:GetAttribute("count"), 3, "the wheel count is recorded for the mouse wheel")
local snippet = _G.ActionWheelsCatcher:GetAttribute("_onmousewheel")
eq(string.find(snippet, "nidx < 1 or nidx > r:GetAttribute(\"count\")", 1, true) ~= nil, true, "mouse wheel stops at the ends")
eq(string.find(snippet, '"next"', 1, true), nil, "and does not use the wrapping next/prev links")
_G.ActionWheelsRoot:SetAttribute("last", "page3")
_G.ActionWheelsRoot._OnHide()
eq(AW.P().lastWheel, "w3", "closing saves the wheel that was showing")
AW.ApplyLayout()
eq(_G.ActionWheelsRoot:GetAttribute("last"), "page3", "and it is restored after a layout refresh / reload")
AW.Slash("wheel select w3")
AW.Slash("wheel move up")
AW.Slash("wheel move up")
eq(_G.ActionWheelsRoot:GetAttribute("last"), "page1", "after reordering it still points at the same wheel")
AW.Slash("wheel delete")
eq(_G.ActionWheelsRoot:GetAttribute("last") ~= nil, true, "a deleted last wheel falls back to the first wheel")
-- one-time migration of the old default
ActionWheelsDB.openFirstMigrated = nil
ActionWheelsDB.profile.settings.openFirst = "selected"
AW.InitDB()
eq(AW.P().settings.openFirst, "last", "old default migrated once")
AW.Slash("opens selected")
AW.InitDB()
eq(AW.P().settings.openFirst, "selected", "and a later choice is kept")
AW.Slash("opens last")
AW.Slash("reset")

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
eq(_G.ActionWheelsP1S2:GetAttribute("macrotext"), "/cast Aimed Shot", "dropped spell reaches the secure button")
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
