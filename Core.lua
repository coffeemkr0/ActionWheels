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

function AW.P() return ActionWheelsDB.profile end

local function Sanitize(p)
	fill(p.settings, AW.DEFAULT_SETTINGS)
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
	Sanitize(ActionWheelsDB.profile)
end

function AW.ResetProfile()
	ActionWheelsDB.profile = AW.NewProfile()
	Sanitize(ActionWheelsDB.profile)
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

AW.OnEvent = function(_, event, a1)
	if event == "ADDON_LOADED" then
		if a1 == "ActionWheels" then AW.InitDB() end
	elseif event == "PLAYER_LOGIN" then
		if not (ActionWheelsDB and ActionWheelsDB.profile) then AW.InitDB() end
		AW.BuildWheel()
		AW.ApplyLayout()
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
	"/aw mode toggle|hold   /aw at cursor|center   /aw scale <0.5-2>",
	"/aw reset   (restore the starter wheel)",
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
		if rest ~= "toggle" and rest ~= "hold" then return AW.Print("Usage: /aw mode toggle|hold") end
		p.settings.openMode = rest
		return done(true, "open mode: " .. rest)
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
		elseif sub == "delete" then
			local gone = def.name
			local ok, err = AW.DeleteWheel(p, p.current)
			if not ok then return AW.Print(err) end
			return done(true, "deleted '" .. gone .. "'")
		end
		AW.Print("Usage: /aw wheel new <name> | select <name or number> | rename <name> | delete")
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
