-- Core: namespace, saved variables, events, slash commands.
ActionWheels = ActionWheels or {}
local AW = ActionWheels

AW.DB_VERSION = 1

BINDING_HEADER_ACTIONWHEELS = "ActionWheels"
_G["BINDING_NAME_CLICK ActionWheelsToggle:LeftButton"] = "Action wheel (open / hold)"
_G["BINDING_NAME_CLICK ActionWheelsNext:LeftButton"] = "Next wheel (while open)"
_G["BINDING_NAME_CLICK ActionWheelsPrev:LeftButton"] = "Previous wheel (while open)"

function AW.Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ActionWheels:|r " .. tostring(msg))
	end
end

function AW.Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = AW.Copy(x) end
	return t
end

-- Fill keys missing from dst with copies from src (recursing into non-array tables).
local function fill(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			dst[k] = AW.Copy(v)
		elseif type(v) == "table" and type(dst[k]) == "table" and v[1] == nil then
			fill(dst[k], v)
		end
	end
end
AW.FillDefaults = fill

function AW.InCombat()
	if InCombatLockdown and InCombatLockdown() then return true end
	return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
end

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
function AW.NewProfile()
	local wheels, order = AW.DefaultWheels()
	return { wheels = wheels, order = order, current = order[1], settings = AW.Copy(AW.DEFAULT_SETTINGS) }
end

-- Account-wide by default; a character can switch to its own copy (ActionWheelsCharDB).
function AW.P()
	if ActionWheelsCharDB and ActionWheelsCharDB.useChar and ActionWheelsCharDB.profile then
		return ActionWheelsCharDB.profile
	end
	return ActionWheelsDB.profile
end

function AW.UsingCharProfile()
	return ActionWheelsCharDB and ActionWheelsCharDB.useChar and ActionWheelsCharDB.profile and true or false
end

function AW.SetCharProfile(on)
	ActionWheelsCharDB = ActionWheelsCharDB or {}
	if on and not ActionWheelsCharDB.profile then
		ActionWheelsCharDB.profile = AW.Copy(ActionWheelsDB.profile) -- start from the account wheels
	end
	ActionWheelsCharDB.useChar = on and true or false
end

local function Sanitize(p)
	fill(p.settings, AW.DEFAULT_SETTINGS)
	local om = p.settings.openMode
	if om ~= "toggle" and om ~= "hold" and om ~= "auto" then p.settings.openMode = "toggle" end
	local cm = p.settings.closeMode
	if cm ~= "success" and cm ~= "click" and cm ~= "never" then p.settings.closeMode = "success" end
	if not p.wheels[p.current] then p.current = p.order[1] end
	for _, w in pairs(p.wheels) do
		w.items = w.items or {}
		w.slots = math.max(AW.MINSLOTS, math.min(AW.MAXSLOTS, w.slots or 8))
	end
end

function AW.InitDB()
	ActionWheelsDB = ActionWheelsDB or {}
	if not ActionWheelsDB.profile then ActionWheelsDB.profile = AW.NewProfile() end
	ActionWheelsDB.version = AW.DB_VERSION
	ActionWheelsDB.minimap = ActionWheelsDB.minimap or {}
	fill(ActionWheelsDB.minimap, { hide = false, angle = 215 })
	ActionWheelsDB.launcher = ActionWheelsDB.launcher or {}
	fill(ActionWheelsDB.launcher, { hide = true, locked = false })
	Sanitize(ActionWheelsDB.profile)
	ActionWheelsCharDB = ActionWheelsCharDB or {}
	if ActionWheelsCharDB.profile then Sanitize(ActionWheelsCharDB.profile) end
end

function AW.ResetProfile()
	local fresh = AW.NewProfile()
	if AW.UsingCharProfile() then ActionWheelsCharDB.profile = fresh else ActionWheelsDB.profile = fresh end
	Sanitize(fresh)
end

---------------------------------------------------------------------------
-- Dropping a spell / item / macro from the cursor onto a slot
---------------------------------------------------------------------------
function AW.DropOnSlot(wheelId, idx)
	if AW.InCombat() then AW.Print("Slots can't be changed during combat.") return false end
	local slot, why = AW.SlotFromCursor()
	if not slot then if why then AW.Print(why) end return false end
	local def = AW.P().wheels[wheelId]
	if not def or idx < 1 or idx > def.slots then return false end
	def.items[idx] = slot
	if ClearCursor then ClearCursor() end
	AW.ApplyLayout()
	if AW.RefreshConfig then AW.RefreshConfig() end
	AW.Print("slot " .. idx .. " = " .. AW.DescribeSlot(slot))
	return true
end

---------------------------------------------------------------------------
-- Key bindings and the settings window
---------------------------------------------------------------------------
function AW.OpenKeyBindings()
	if AW.HideConfig then AW.HideConfig() end -- our window would sit on top of it
	local function try(fn) return (pcall(fn)) end
	if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
		if try(function() Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID) end) then return "settings" end
	end
	if KeyBindingFrame or KeyBindingFrame_LoadUI then
		local ok = try(function()
			if KeyBindingFrame_LoadUI then KeyBindingFrame_LoadUI() end
			ShowUIPanel(KeyBindingFrame)
		end)
		if ok and KeyBindingFrame then return "frame" end
	end
	if GameMenuButtonKeybindings and GameMenuButtonKeybindings.Click then
		if try(function() GameMenuButtonKeybindings:Click() end) then return "menu" end
	end
	AW.Print("Press Esc > Options > Key Bindings > AddOns > ActionWheels.")
end

function AW.OpenConfig()
	if AW.ShowConfig then AW.ShowConfig() end
end

---------------------------------------------------------------------------
-- Wheel management
---------------------------------------------------------------------------
-- Find a wheel id by id, 1-based position, or (case-insensitive) name.
function AW.FindWheel(p, key)
	key = key or ""
	if p.wheels[key] then return key end
	local n = tonumber(key)
	if n and p.order[n] then return p.order[n] end
	local lower = string.lower(key)
	for _, id in ipairs(p.order) do
		if string.lower(p.wheels[id].name) == lower then return id end
	end
end

function AW.NewWheel(p, name)
	if #p.order >= AW.MAXWHEELS then return nil, "At most " .. AW.MAXWHEELS .. " wheels." end
	local n = #p.order + 1
	local id = "w" .. n
	while p.wheels[id] do n = n + 1; id = "w" .. n end
	p.wheels[id] = { name = (name ~= "" and name) or ("Wheel " .. (#p.order + 1)), slots = 8, items = {} }
	p.order[#p.order + 1] = id
	return id
end

function AW.DeleteWheel(p, id)
	if #p.order <= 1 then return false, "You need at least one wheel." end
	p.wheels[id] = nil
	for i, v in ipairs(p.order) do if v == id then table.remove(p.order, i) break end end
	for _, w in pairs(p.wheels) do -- sub-wheel slots pointing at it become empty
		for i, slot in pairs(w.items) do
			if slot.type == "wheel" and slot.wheel == id then w.items[i] = nil end
		end
	end
	if p.current == id then p.current = p.order[1] end
	return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
AW.eventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- the action-bar slot lookup is cached; any change to the bars invalidates it
for _, ev in ipairs({ "ACTIONBAR_SLOT_CHANGED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do pcall(frame.RegisterEvent, frame, ev) end
-- keep the "which buffs are on me" memory fresh (used for the active-aspect highlight)
if not (frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")) then
	pcall(frame.RegisterEvent, frame, "UNIT_AURA")
end
if not (frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")) then
	pcall(frame.RegisterEvent, frame, "UNIT_SPELLCAST_SUCCEEDED")
end

local lastAura = 0
AW.OnEvent = function(_, event, a1, a2, a3)
	if event == "UNIT_AURA" then
		if a1 ~= "player" or not AW.UpdateBuffCache then return end
		if AW.OnAura then AW.OnAura(a2) end -- every event: removals must not be missed
		local now = GetTime()
		if now - lastAura < 0.25 then return end
		lastAura = now
		AW.UpdateBuffCache()
	elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
		AW.actionSlots = {}
		AW.spellIdCache = {}
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if a1 ~= "player" or not AW.OnCastSucceeded then return end
		if AW.debug then AW.Print("cast succeeded (spell id " .. ((issecretvalue and issecretvalue(a3)) and "hidden" or tostring(a3)) .. ")") end
		AW.OnCastSucceeded(a3)
	elseif event == "ADDON_LOADED" then
		if a1 == "ActionWheels" then AW.InitDB() end
	elseif event == "PLAYER_LOGIN" then
		if not (ActionWheelsDB and ActionWheelsDB.profile) then AW.InitDB() end
		AW.BuildWheel()
		AW.ApplyLayout()
		AW.UpdateBuffCache()
		if AW.UpdateMinimap then AW.UpdateMinimap() end
		if not ActionWheelsDB.welcomed then
			ActionWheelsDB.welcomed = true -- never nag twice
			if GetBindingKey and not GetBindingKey("CLICK ActionWheelsToggle:LeftButton") then
				AW.Print("Welcome! Bind a key under Esc > Key Bindings > AddOns > ActionWheels, then type /aw to set up your wheel.")
			end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if AW.HideConfig then AW.HideConfig() end -- editing is locked in combat
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- changes made during combat were held back; apply them now
		if AW.pendingApply then AW.ApplyLayout() end
	end
end
frame:SetScript("OnEvent", AW.OnEvent)

---------------------------------------------------------------------------
-- Slash commands (until the editor arrives: /aw set 1 spell Aimed Shot)
---------------------------------------------------------------------------
local HELP = {
	"/aw set <slot> spell <name>   - e.g. /aw set 1 spell Aimed Shot",
	"/aw set <slot> item <name>    - e.g. /aw set 2 item Hearthstone",
	"/aw set <slot> macro <text>   - e.g. /aw set 3 macro /cast Hunter's Mark",
	"/aw set <slot> pet <command>  - attack, follow, stay, passive, defensive, aggressive, assist",
	"/aw set <slot> wheel <name or number>  - a slot that opens another wheel",
	"/aw wheels   /aw wheel new|select|rename|delete   (wheels you page through with the hub arrows)",
	"/aw clear <slot>   /aw list   /aw slots <4-12>",
	"/aw mode toggle|hold|auto   /aw at cursor|center   /aw scale <0.5-2>   /aw close success|click|never",
	"/aw wheel auto [mounted]   - open this wheel first when a macro condition holds (off to clear)",
	"/aw launcher [lock|unlock|reset]   (small on-screen button that opens the wheel)",
	"/click ActionWheelsOpen   in a macro on an action bar opens the wheel (…Open2 = 2nd wheel)",
	"/aw minimap   /aw keys   /aw buffs   /aw inspect <spell>   /aw debug   /aw reset   (restore the starter wheel)",
	"/aw (no arguments) opens the settings window",
}

local function parse(msg)
	msg = string.gsub(msg or "", "^%s+", "")
	local cmd, rest = string.match(msg, "^(%S*)%s*(.-)%s*$")
	return string.lower(cmd or ""), rest or ""
end

function AW.Slash(msg)
	local cmd, rest = parse(msg)
	local p = AW.P()
	local def = p.wheels[p.current]
	local function done(ok, text)
		if text then AW.Print(text) end
		if ok then AW.ApplyLayout() end
	end
	if cmd == "set" then
		local idx, kind, arg = string.match(rest, "^(%d+)%s+(%a+)%s*(.*)$")
		idx = tonumber(idx)
		if not idx or idx < 1 or idx > def.slots then
			return AW.Print("Slot must be a number from 1 to " .. def.slots .. ".")
		end
		local slot, err = AW.MakeSlot(string.lower(kind), arg)
		if not slot then return AW.Print(err) end
		if slot.type == "wheel" then
			local id = AW.FindWheel(p, slot.wheel)
			if not id then return AW.Print("No wheel '" .. slot.wheel .. "'. See /aw wheels.") end
			if id == p.current then return AW.Print("A wheel can't open itself.") end
			slot.wheel = id
		end
		def.items[idx] = slot
		local held = AW.InCombat() and " (it will apply when combat ends)" or ""
		return done(true, "slot " .. idx .. " = " .. AW.DescribeSlot(slot) .. held)
	elseif cmd == "clear" then
		local idx = tonumber(rest)
		if not idx or idx < 1 or idx > def.slots then return AW.Print("Usage: /aw clear <slot>") end
		def.items[idx] = nil
		return done(true, "slot " .. idx .. " cleared")
	elseif cmd == "list" then
		for i = 1, def.slots do
			AW.Print(i .. ": " .. AW.DescribeSlot(def.items[i]))
		end
	elseif cmd == "slots" then
		local n = tonumber(rest)
		if not n then return AW.Print("Usage: /aw slots <" .. AW.MINSLOTS .. "-" .. AW.MAXSLOTS .. ">") end
		def.slots = math.max(AW.MINSLOTS, math.min(AW.MAXSLOTS, math.floor(n)))
		return done(true, "the wheel now has " .. def.slots .. " slots")
	elseif cmd == "mode" then
		if rest ~= "toggle" and rest ~= "hold" and rest ~= "auto" then
			return AW.Print("Usage: /aw mode toggle|hold|auto  (auto: hold in combat, press-to-open out of combat)")
		end
		p.settings.openMode = rest
		return done(true, "open mode: " .. rest)
	elseif cmd == "close" then
		if rest ~= "success" and rest ~= "click" and rest ~= "never" then
			return AW.Print("Usage: /aw close success|click|never  (success: a spell slice stays open until it casts)")
		end
		p.settings.closeMode = rest
		return done(true, "after a click: " .. rest)
	elseif cmd == "at" then
		if rest ~= "cursor" and rest ~= "center" then return AW.Print("Usage: /aw at cursor|center") end
		p.settings.openAt = rest
		return done(true, "the wheel opens at the " .. rest)
	elseif cmd == "scale" then
		local s = tonumber(rest)
		if not s then return AW.Print("Usage: /aw scale <0.5-2>") end
		p.settings.scale = math.max(0.5, math.min(2, s))
		return done(true, "scale " .. p.settings.scale)
	elseif cmd == "wheels" then
		for i, id in ipairs(p.order) do
			AW.Print(i .. ": " .. p.wheels[id].name .. (id == p.current and "  <- editing / opens first" or ""))
		end
	elseif cmd == "wheel" then
		local sub, arg = string.match(rest, "^(%S*)%s*(.-)$")
		sub = string.lower(sub or "")
		if sub == "new" then
			local id, err = AW.NewWheel(p, arg)
			if not id then return AW.Print(err) end
			p.current = id
			return done(true, "created '" .. p.wheels[id].name .. "' and selected it")
		elseif sub == "select" then
			local id = AW.FindWheel(p, arg)
			if not id then return AW.Print("No wheel '" .. arg .. "'. See /aw wheels.") end
			p.current = id
			return done(true, "now editing '" .. p.wheels[id].name .. "'; it opens first")
		elseif sub == "rename" then
			if arg == "" then return AW.Print("Usage: /aw wheel rename <name>") end
			def.name = arg
			return done(true, "renamed to '" .. arg .. "'")
		elseif sub == "auto" then
			if arg == "" or string.lower(arg) == "off" then
				def.auto = nil
				return done(true, "'" .. def.name .. "' no longer opens automatically")
			end
			if not AW.ValidCondition(arg) then
				return AW.Print("Use macro conditions in brackets, e.g. /aw wheel auto [mounted]  or  [stance:1,combat]")
			end
			def.auto = arg
			return done(true, "'" .. def.name .. "' opens first when " .. arg)
		elseif sub == "delete" then
			local gone = def.name
			local ok, err = AW.DeleteWheel(p, p.current)
			if not ok then return AW.Print(err) end
			return done(true, "deleted '" .. gone .. "'")
		end
		AW.Print("Usage: /aw wheel new <name> | select <name or number> | rename <name> | auto <[condition]|off> | delete")
	elseif cmd == "minimap" then
		ActionWheelsDB.minimap.hide = not ActionWheelsDB.minimap.hide
		if AW.UpdateMinimap then AW.UpdateMinimap() end
		return AW.Print("minimap button " .. (ActionWheelsDB.minimap.hide and "hidden" or "shown"))
	elseif cmd == "debug" then
		AW.debug = not AW.debug
		return AW.Print("debug " .. (AW.debug and "on: clicking a slice prints what it received" or "off"))
	elseif cmd == "buffs" then
		for _, line in ipairs(AW.BuffReport()) do AW.Print(line) end
	elseif cmd == "inspect" then
		if rest == "" then return AW.Print("Usage: /aw inspect <spell name>") end
		for _, line in ipairs(AW.InspectSpell(rest)) do AW.Print(line) end
	elseif cmd == "launcher" then
		local L = ActionWheelsDB.launcher
		if rest == "lock" or rest == "unlock" then
			L.locked = (rest == "lock")
			return AW.Print("launcher " .. (L.locked and "locked" or "unlocked: Shift + drag to move it"))
		elseif rest == "reset" then
			L.x, L.y = nil, nil
		else
			L.hide = not L.hide
		end
		if AW.InCombat() then AW.pendingApply = true return AW.Print("The launcher will update when combat ends.") end
		AW.PlaceLauncher()
		if AW.RefreshConfig then AW.RefreshConfig() end
		return AW.Print("on-screen button " .. (L.hide and "hidden" or "shown (Shift + drag to move, /aw launcher lock to fix it)"))
	elseif cmd == "keys" then
		AW.OpenKeyBindings()
	elseif cmd == "" or cmd == "config" then
		AW.OpenConfig()
	elseif cmd == "reset" then
		AW.ResetProfile()
		return done(true, "starter wheel restored")
	else
		AW.Print("Bind a key: Esc > Key Bindings > AddOns > ActionWheels. Commands:")
		for _, l in ipairs(HELP) do AW.Print(l) end
	end
end

SLASH_ACTIONWHEELS1 = "/aw"
SLASH_ACTIONWHEELS2 = "/actionwheels"
SlashCmdList["ACTIONWHEELS"] = AW.Slash
