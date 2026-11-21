-- Config: the settings window (Wheels editor / Settings / Share). Out of combat only.
ActionWheels = ActionWheels or {}
local AW = ActionWheels

local frame
local tabs, tabButtons = {}, {}
local loading = false
local refreshers = {}
local ctr = 0
local sel = 1          -- selected slot in the wheel editor
local formKind = "spell"

local function S() return AW.P().settings end
local function Name(prefix) ctr = ctr + 1; return "ActionWheelsCfg" .. prefix .. ctr end
local function RefreshAll()
	local was = loading
	loading = true
	for _, r in ipairs(refreshers) do r() end
	loading = was
end
local function OnChanged() AW.ApplyLayout() end
local function Locked()
	if AW.InCombat() then AW.Print("Editing is locked during combat.") return true end
	return false
end

---------------------------------------------------------------------------
-- widgets (each registers a refresher that re-reads its value)
---------------------------------------------------------------------------
local function Text(parent, text, x, y, template, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	if width then fs:SetWidth(width) end
	fs:SetText(text)
	return fs
end

local function Slider(parent, label, x, y, min, max, step, get, set, fmt)
	local name = Name("Slider")
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetWidth(210)
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	local lo, hi, txt = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
	if lo then lo:SetText(min) end
	if hi then hi:SetText(max) end
	local function caption(v) if txt then txt:SetText(label .. ": " .. string.format(fmt or "%d", v)) end end
	s:SetScript("OnValueChanged", function(_, v)
		caption(v)
		if loading or Locked() then return end
		set(v)
		OnChanged()
	end)
	refreshers[#refreshers + 1] = function() s:SetValue(get()); caption(get()) end
	return s
end

local function Check(parent, label, x, y, get, set)
	local name = Name("Check")
	local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local t = _G[name .. "Text"]
	if t then t:SetText(label) end
	c:SetScript("OnClick", function()
		if loading then return end
		set(c:GetChecked() and true or false)
	end)
	refreshers[#refreshers + 1] = function() c:SetChecked(get() and true or false) end
	return c
end

-- left-click cycles forward, right-click backward
local function Cycle(parent, label, x, y, options, get, set, width, labelWidth)
	Text(parent, label, x, y - 5, "GameFontNormalSmall")
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(width or 150)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (labelWidth or 160), y)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function idx()
		local v = get()
		for i, o in ipairs(options) do if o[1] == v then return i end end
		return 1
	end
	b:SetScript("OnClick", function(_, button)
		if Locked() then return end
		local n, i = #options, idx()
		i = (button == "RightButton") and ((i - 2) % n) + 1 or (i % n) + 1
		set(options[i][1])
		b:SetText(options[i][2])
		OnChanged()
	end)
	refreshers[#refreshers + 1] = function() b:SetText(options[idx()][2]) end
	return b
end

local function Button(parent, text, x, y, w, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(w)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", fn)
	return b
end

-- A text box that saves when you leave it (Enter, Tab or clicking elsewhere) and cancels on Escape.
-- onCommit(text) applies the change; onCancel() puts the saved text back (used by Escape).
local function Edit(parent, x, y, w, onCommit, onCancel)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetWidth(w)
	e:SetHeight(20)
	e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	e:SetAutoFocus(false)
	e.cancelled = false
	e:SetScript("OnEscapePressed", function()
		e.cancelled = true
		e:ClearFocus()
	end)
	if onCommit then
		e:SetScript("OnEnterPressed", function() e:ClearFocus() end) -- leaving the box commits it
		e:SetScript("OnEditFocusLost", function()
			if e.cancelled then
				e.cancelled = false
				if onCancel then onCancel() end
				return
			end
			onCommit(e:GetText())
		end)
	end
	return e
end

---------------------------------------------------------------------------
-- Wheels tab: wheel picker + a preview ring you can drop things onto + the slot form
---------------------------------------------------------------------------
local ringButtons = {}
local KINDS = {
	{ "spell", "Spell", "Spell name, e.g. Aimed Shot. Or drag one from your spellbook onto a slot in the ring." },
	{ "item", "Item", "Item name, e.g. Hearthstone. Or drag an item from your bags onto a slot." },
	{ "macro", "Macro", "Macro text; type \\n for a new line. Start with #showtooltip Spell to borrow that spell's icon and cooldown. Or drag a macro onto a slot." },
	{ "pet", "Pet", "attack, follow, stay, passive, defensive, aggressive or assist" },
	{ "wheel", "Wheel", "Name or number of the wheel this slot opens." },
}

local function Cur()
	local p = AW.P()
	return p, p.current, p.wheels[p.current]
end

local function EscapeNewlines(s) return (string.gsub(s or "", "\n", "\\n")) end
local function UnescapeNewlines(s) return (string.gsub(s or "", "\\n", "\n")) end

local function LoadForm()
	local _, _, def = Cur()
	local slot = def.items[sel]
	frame.slotTitle:SetText("Slot " .. sel .. ": " .. AW.DescribeSlot(slot))
	formKind = (slot and slot.type) or formKind
	local value = ""
	if slot then
		if slot.type == "macro" then value = EscapeNewlines(slot.macrotext)
		elseif slot.type == "pet" then value = slot.pet or ""
		elseif slot.type == "wheel" then
			local w = AW.P().wheels[slot.wheel]
			value = w and w.name or ""
		else value = slot[slot.type] or "" end
	end
	frame.valueBox:SetText(value)
	frame.labelBox:SetText((slot and slot.label) or "")
	frame.iconBox:SetText(slot and slot.icon and tostring(slot.icon) or "")
	for i, k in ipairs(KINDS) do
		if k[1] == formKind then frame.kindButtons[i]:LockHighlight(); frame.hint:SetText(k[3])
		else frame.kindButtons[i]:UnlockHighlight() end
	end
end

local function RefreshWheels()
	local p, id, def = Cur()
	local pos = 1
	for i, v in ipairs(p.order) do if v == id then pos = i end end
	frame.pos:SetText(pos .. "/" .. #p.order)
	frame.wheelName:SetText(def.name)
	frame.autoBox:SetText(def.auto or "")
	frame.wheelBtn:SetChecked(def.launcher and def.launcher.show and true or false)
	frame.slotCount:SetText(def.slots .. " slots")
	if sel > def.slots then sel = def.slots end
	local n = def.slots
	local step = 2 * math.pi / n
	for i = 1, AW.MAXSLOTS do
		local b = ringButtons[i]
		if i <= n then
			local a = (i - 1) * step
			b:ClearAllPoints()
			b:SetPoint("CENTER", frame.ring, "CENTER", math.sin(a) * 100, math.cos(a) * 100)
			local slot = def.items[i]
			local icon = AW.SlotIcon(slot)
			if icon then b.icon:SetTexture(icon); b.icon:Show(); b.plus:SetText("")
			else b.icon:Hide(); b.plus:SetText("+") end
			if i == sel then b.ring:SetVertexColor(0.3, 1, 0.3, 1) else b.ring:SetVertexColor(0.4, 0.45, 0.55, 1) end
			b:Show()
		else
			b:Hide()
		end
	end
	LoadForm()
	if frame.refreshColor then frame.refreshColor() end
	if frame.refreshTrack then frame.refreshTrack() end
end

local function SelectSlot(i)
	sel = i
	RefreshWheels()
end

local function SaveForm()
	if Locked() then return end
	local p, _, def = Cur()
	local value = frame.valueBox:GetText()
	if formKind == "macro" then value = UnescapeNewlines(value) end
	local slot, err = AW.MakeSlot(formKind, value)
	if not slot then frame.status:SetText("|cffff6060" .. err .. "|r") return end
	if slot.type == "wheel" then
		local wid = AW.FindWheel(p, slot.wheel)
		if not wid then frame.status:SetText("|cffff6060No wheel called '" .. slot.wheel .. "'.|r") return end
		if wid == p.current then frame.status:SetText("|cffff6060A wheel can't open itself.|r") return end
		slot.wheel = wid
	end
	local label = frame.labelBox:GetText()
	if label ~= "" then slot.label = string.sub(label, 1, 24) end
	local icon = frame.iconBox:GetText()
	if icon ~= "" then
		if tonumber(icon) then slot.icon = tonumber(icon)
		elseif string.find(icon, "[\\/]") then slot.icon = icon
		else slot.icon = "Interface\\Icons\\" .. icon end
	end
	def.items[sel] = slot
	frame.status:SetText("|cff60ff60Saved.|r")
	AW.ApplyLayout()
	RefreshWheels()
end

local function BuildWheelsTab(t)
	-- wheel picker row
	Text(t, "Wheel", 4, -10, "GameFontNormalSmall")
	Button(t, "<", 44, -6, 24, function()
		if Locked() then return end
		local p = AW.P()
		local i = 1
		for k, v in ipairs(p.order) do if v == p.current then i = k end end
		p.current = p.order[(i - 2) % #p.order + 1]
		AW.ApplyLayout(); RefreshWheels()
	end)
	frame.pos = Text(t, "1/1", 72, -10, "GameFontHighlightSmall")
	Button(t, ">", 100, -6, 24, function()
		if Locked() then return end
		local p = AW.P()
		local i = 1
		for k, v in ipairs(p.order) do if v == p.current then i = k end end
		p.current = p.order[i % #p.order + 1]
		AW.ApplyLayout(); RefreshWheels()
	end)
	frame.wheelName = Edit(t, 138, -6, 150, function(txt)
		if Locked() or txt == "" then return end
		local _, _, def = Cur()
		def.name = string.sub(txt, 1, 40)
		AW.ApplyLayout(); RefreshWheels()
	end, function() RefreshWheels() end)
	Button(t, "New", 296, -6, 50, function()
		if Locked() then return end
		local p = AW.P()
		local id, err = AW.NewWheel(p, "")
		if not id then AW.Print(err) return end
		p.current = id
		AW.ApplyLayout(); sel = 1; RefreshWheels()
	end)
	local del = Button(t, "Delete", 350, -6, 56, nil)
	del:SetScript("OnClick", function()
		if Locked() then return end
		if not del.armed then
			del.armed = true
			del:SetText("Sure?")
			AW.After(3, function() del.armed = false; del:SetText("Delete") end)
			return
		end
		del.armed = false
		del:SetText("Delete")
		local p = AW.P()
		local ok, err = AW.DeleteWheel(p, p.current)
		if not ok then AW.Print(err) return end
		AW.ApplyLayout(); sel = 1; RefreshWheels()
	end)
	Button(t, "-", 414, -6, 22, function()
		if Locked() then return end
		local _, _, def = Cur()
		def.slots = math.max(AW.MINSLOTS, def.slots - 1)
		AW.ApplyLayout(); RefreshWheels()
	end)
	frame.slotCount = Text(t, "8 slots", 440, -10, "GameFontHighlightSmall")
	Button(t, "+", 496, -6, 22, function()
		if Locked() then return end
		local _, _, def = Cur()
		def.slots = math.min(AW.MAXSLOTS, def.slots + 1)
		AW.ApplyLayout(); RefreshWheels()
	end)

	Text(t, "Opens first when (optional):", 4, -38, "GameFontNormalSmall")
	frame.autoBox = Edit(t, 170, -34, 180, function(txt)
		if Locked() then return end
		local _, _, def = Cur()
		if txt == "" then def.auto = nil
		elseif AW.ValidCondition(txt) then def.auto = txt
		else AW.Print("Use macro conditions in brackets, e.g. [mounted] or [stance:1,combat]") end
		AW.ApplyLayout(); RefreshWheels()
	end, function() RefreshWheels() end)
	Text(t, "e.g. [mounted]  [combat]  [stance:1]", 358, -38, "GameFontDisableSmall")

	-- on-screen button and action-bar macro for this wheel
	local wcName = Name("WheelBtn")
	local wc = CreateFrame("CheckButton", wcName, t, "UICheckButtonTemplate")
	wc:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -58)
	local wct = _G[wcName .. "Text"]
	if wct then wct:SetText("Movable on-screen button for this wheel") end
	wc:SetScript("OnClick", function()
		if loading or Locked() then wc:SetChecked(not wc:GetChecked()) return end
		local _, _, def = Cur()
		def.launcher = def.launcher or {}
		def.launcher.show = wc:GetChecked() and true or false
		AW.PlaceLaunchers()
	end)
	frame.wheelBtn = wc
	Button(t, "Put on action bar", 330, -60, 130, function()
		if Locked() then return end
		local _, id = Cur()
		AW.MakeActionBarMacro(id)
	end)
	Button(t, "Move <", 4, -84, 64, function()
		if Locked() then return end
		local p = AW.P()
		if AW.MoveWheel(p, p.current, -1) then AW.ApplyLayout(); RefreshWheels() end
	end)
	Button(t, "Move >", 72, -84, 64, function()
		if Locked() then return end
		local p = AW.P()
		if AW.MoveWheel(p, p.current, 1) then AW.ApplyLayout(); RefreshWheels() end
	end)
	Button(t, "Copy wheel", 140, -84, 90, function()
		if Locked() then return end
		local p = AW.P()
		local id, err = AW.DuplicateWheel(p, p.current)
		if not id then AW.Print(err) return end
		p.current = id
		AW.ApplyLayout(); sel = 1; RefreshWheels()
	end)
	Text(t, "(buttons: Shift + drag moves them)", 240, -88, "GameFontDisableSmall")

	-- preview ring
	frame.ring = CreateFrame("Frame", nil, t)
	frame.ring:SetWidth(10)
	frame.ring:SetHeight(10)
	frame.ring:SetPoint("TOPLEFT", t, "TOPLEFT", 150, -233)
	for i = 1, AW.MAXSLOTS do
		local b = CreateFrame("Button", nil, t)
		b:SetWidth(42)
		b:SetHeight(42)
		b:RegisterForClicks("LeftButtonUp")
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints(b)
		b.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
		b.bg:SetVertexColor(0.05, 0.05, 0.09, 0.95)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetWidth(36)
		b.icon:SetHeight(36)
		b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.ring = AW.SquareBorder(b, "OVERLAY", 2)
		b.plus = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.plus:SetPoint("CENTER", b, "CENTER", 0, 0)
		local function onDrop()
			if GetCursorInfo and GetCursorInfo() then
				local _, id = Cur()
				if AW.DropOnSlot(id, i) then sel = i; RefreshWheels() end
				return true
			end
		end
		b:SetScript("OnReceiveDrag", onDrop)
		b:SetScript("OnClick", function() if not onDrop() then SelectSlot(i) end end)
		ringButtons[i] = b
	end
	local hint = Text(t, "Drag a spell, item or macro onto a slot, or pick a slot and fill in the form.", 4, -380, "GameFontHighlightSmall", 280)

	-- slot form
	frame.slotTitle = Text(t, "Slot 1", 310, -98, "GameFontNormal", 240)
	frame.kindButtons = {}
	for i, k in ipairs(KINDS) do
		local b = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
		b:SetWidth(46)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", t, "TOPLEFT", 310 + (i - 1) * 48, -124)
		b:SetText(k[2])
		b:SetScript("OnClick", function() formKind = k[1]; LoadForm() end)
		frame.kindButtons[i] = b
	end
	Text(t, "Value", 310, -154, "GameFontNormalSmall")
	frame.valueBox = Edit(t, 310, -170, 230)
	frame.valueBox:SetMaxLetters(255)
	frame.hint = Text(t, "", 310, -196, "GameFontHighlightSmall", 236)
	Text(t, "Label (optional)", 310, -242, "GameFontNormalSmall")
	frame.labelBox = Edit(t, 310, -258, 110)
	frame.labelBox:SetMaxLetters(24)
	Text(t, "Icon (optional)", 430, -242, "GameFontNormalSmall")
	frame.iconBox = Edit(t, 430, -258, 110)
	Button(t, "Save slot", 310, -292, 100, SaveForm)
	Button(t, "Clear slot", 416, -292, 100, function()
		if Locked() then return end
		local _, _, def = Cur()
		def.items[sel] = nil
		frame.status:SetText("")
		AW.ApplyLayout(); RefreshWheels()
	end)
	-- border colour of this slot
	local colorOptions = { { "none", "None" } }
	for _, nm in ipairs(AW.COLOR_ORDER) do colorOptions[#colorOptions + 1] = { nm, string.upper(string.sub(nm, 1, 1)) .. string.sub(nm, 2) } end
	Cycle(t, "Border colour", 310, -320, colorOptions,
		function()
			local _, _, def = Cur()
			local sl = def.items[sel]
			return (sl and sl.color) or "none"
		end,
		function(v)
			local _, _, def = Cur()
			local sl = def.items[sel]
			if not sl then return end
			sl.color = (v ~= "none") and v or nil
		end, 80, 90)
	frame.refreshColor = refreshers[#refreshers]
	local trackCheck = Check(t, "On the cooldown strip", 304, -376,
		function()
			local _, _, def = Cur()
			local sl = def.items[sel]
			return sl and sl.track and true or false
		end,
		function(v)
			if Locked() then return end
			local _, _, def = Cur()
			local sl = def.items[sel]
			if not sl then return end
			sl.track = v and true or nil
			AW.TrackerRefresh()
		end)
	frame.refreshTrack = refreshers[#refreshers]
	Button(t, "Swap <", 310, -350, 70, function()
		if Locked() then return end
		local _, id, def = Cur()
		local other = (sel - 2) % def.slots + 1
		if AW.SwapSlots(AW.P(), id, sel, other) then sel = other; AW.ApplyLayout(); RefreshWheels() end
	end)
	Button(t, "Swap >", 384, -350, 70, function()
		if Locked() then return end
		local _, id, def = Cur()
		local other = sel % def.slots + 1
		if AW.SwapSlots(AW.P(), id, sel, other) then sel = other; AW.ApplyLayout(); RefreshWheels() end
	end)
	frame.status = Text(t, "", 458, -352, "GameFontHighlightSmall", 90)
	refreshers[#refreshers + 1] = RefreshWheels
end

-- Open the editor on a given slot (the wheel's right-click menu uses this).
function AW.EditSlot(wheelId, idx)
	if AW.InCombat() then AW.Print("Editing is locked during combat.") return end
	local p = AW.P()
	if not p.wheels[wheelId] then return end
	p.current = wheelId
	AW.ApplyLayout()
	if not frame then AW.BuildConfig() end
	sel = idx
	RefreshAll()
	AW.SelectConfigTab(1)
	frame:Show()
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
local function BuildSettingsTab(t)
	Text(t, "How the wheel opens", 10, -8)
	Cycle(t, "Key behaviour", 20, -32, { { "toggle", "Press to open / close" }, { "hold", "Hold to show" }, { "auto", "Auto (hold in combat)" } },
		function() return S().openMode end, function(v) S().openMode = v end, 190, 140)
	Cycle(t, "Opens at", 20, -62, { { "cursor", "The mouse cursor" }, { "center", "Screen centre" } },
		function() return S().openAt end, function(v) S().openAt = v end, 190, 140)
	Cycle(t, "After clicking a spell", 20, -92, { { "success", "Close when it casts" }, { "click", "Close right away" }, { "never", "Stay open" } },
		function() return S().closeMode end, function(v) S().closeMode = v end, 190, 140)
	Cycle(t, "The key opens", 20, -122, { { "selected", "The wheel I'm editing" }, { "last", "The last wheel I used" } },
		function() return S().openFirst end, function(v) S().openFirst = v end, 190, 140)
	Cycle(t, "Action bar buttons open", 20, -216, { { "center", "At the screen centre" }, { "cursor", "At the mouse cursor" } },
		function() return S().barOpenAt end, function(v) S().barOpenAt = v end, 190, 140)
	Check(t, "Mouse wheel switches wheels", 14, -160,
		function() return S().wheelScroll end,
		function(v) if Locked() then return end S().wheelScroll = v; OnChanged() end)
	Check(t, "Reverse the mouse wheel direction", 14, -186,
		function() return S().wheelReverse end,
		function(v) if Locked() then return end S().wheelReverse = v; OnChanged() end)
	Text(t, "Other", 280, -134)
	Check(t, "Show the minimap button", 276, -158,
		function() return not ActionWheelsDB.minimap.hide end,
		function(v) ActionWheelsDB.minimap.hide = not v; AW.UpdateMinimap() end)
	Check(t, "Separate wheels for this character", 276, -186,
		function() return AW.UsingCharProfile() end,
		function(v)
			if Locked() then return end
			AW.SetCharProfile(v)
			AW.ApplyLayout()
			sel = 1
			RefreshAll()
		end)
	Check(t, "Show a 'last wheel' on-screen button", 276, -216,
		function() return not ActionWheelsDB.launcher.hide end,
		function(v)
			if Locked() then return end
			ActionWheelsDB.launcher.hide = not v
			AW.PlaceLaunchers()
		end)
	Check(t, "Lock its position (Shift+drag moves)", 276, -242,
		function() return ActionWheelsDB.launcher.locked end,
		function(v) ActionWheelsDB.launcher.locked = v end)
	Button(t, "Key bindings...", 280, -276, 110, function() AW.OpenKeyBindings() end)
	Button(t, "Last wheel -> bar", 396, -276, 140, function()
		if Locked() then return end
		AW.MakeActionBarMacro("last")
	end)
	local reset = Button(t, "Restore starter wheel", 280, -306, 160, nil)
	reset:SetScript("OnClick", function()
		if Locked() then return end
		if not reset.armed then
			reset.armed = true
			reset:SetText("Click again to confirm")
			AW.After(3, function() reset.armed = false; reset:SetText("Restore starter wheel") end)
			return
		end
		reset.armed = false
		reset:SetText("Restore starter wheel")
		AW.ResetProfile()
		AW.ApplyLayout()
		sel = 1
		RefreshAll()
	end)
	Text(t, "Wheels edited in the Wheels tab. Key: Esc > Key Bindings > AddOns > ActionWheels.", 10, -366, "GameFontHighlightSmall", 500)
end

---------------------------------------------------------------------------
-- Look tab
---------------------------------------------------------------------------
local function BuildLookTab(t)
	Text(t, "Size and feel", 10, -8)
	Slider(t, "Button size", 20, -40, 40, 110, 1, function() return S().buttonSize end, function(v) S().buttonSize = v end)
	Slider(t, "Minimum ring radius", 20, -80, 70, 200, 1, function() return S().radius end, function(v) S().radius = v end)
	Slider(t, "Whole wheel scale", 20, -120, 0.6, 2, 0.05, function() return S().scale end, function(v) S().scale = v end, "%.2f")
	Slider(t, "Text size", 20, -160, 0.7, 2.5, 0.1, function() return S().fontScale end, function(v) S().fontScale = v end, "%.1f")
	Slider(t, "Centre controls size", 20, -200, 0.8, 2.5, 0.1, function() return S().hubScale end, function(v) S().hubScale = v end, "%.1f")
	Check(t, "Show tooltips when hovering a slot", 14, -266,
		function() return S().tooltips ~= false end, function(v) if Locked() then return end S().tooltips = v end)
	Check(t, "Play sounds (a soft tick between slices, a click on use)", 14, -240,
		function() return S().sounds end, function(v) if Locked() then return end S().sounds = v end)
	Text(t, "The ring grows by itself when the buttons need more room.", 20, -300, "GameFontHighlightSmall", 480)
end

---------------------------------------------------------------------------
-- Tracker tab: the on-screen cooldown strip
---------------------------------------------------------------------------
local function TR() return ActionWheelsDB.tracker end
local function BuildTrackerTab(t)
	Text(t, "Cooldown strip", 10, -8)
	Text(t, "A small row of icons on screen, even with the wheel closed, that shows when your spells are ready again.", 20, -30, "GameFontHighlightSmall", 500)
	Check(t, "Show the cooldown strip", 14, -60,
		function() return not TR().hide end,
		function(v) TR().hide = not v; AW.TrackerRefresh() end)
	Check(t, "Add spells with long cooldowns automatically", 14, -86,
		function() return TR().auto end,
		function(v) TR().auto = v; AW.TrackerRefresh() end)
	Slider(t, "Long means at least (seconds)", 40, -126, 10, 300, 5,
		function() return TR().threshold end, function(v) TR().threshold = v end)
	Slider(t, "Icon size", 40, -166, 24, 64, 1,
		function() return TR().size end, function(v) TR().size = v end)
	Cycle(t, "Grows to the", 30, -200, { { "right", "Right" }, { "down", "Down" }, { "left", "Left" }, { "up", "Up" } },
		function() return TR().dir end, function(v) TR().dir = v; AW.TrackerRefresh() end, 110, 100)
	Check(t, "Flash an icon when it is ready", 14, -234,
		function() return TR().flash end, function(v) TR().flash = v end)
	Check(t, "Play a sound when it is ready", 14, -260,
		function() return TR().sound end, function(v) TR().sound = v end)
	Check(t, "Unlock (shows a blue box to drag; Shift + drag always works)", 14, -286,
		function() return not TR().locked end,
		function(v) TR().locked = not v; AW.TrackerRefresh() end)
	Button(t, "Reset position", 300, -288, 120, function() AW.TrackerResetPosition() end)
	Text(t, "Always show a spell: tick \"On the cooldown strip\" on its slot in the Wheels tab. Spells with long cooldowns also appear while they cool down and for a few seconds after. Items are not tracked yet.", 20, -322, "GameFontHighlightSmall", 500)
end

---------------------------------------------------------------------------
-- Share tab (import / export)
---------------------------------------------------------------------------
local pendingImport

local function BuildShareTab(t)
	Text(t, "Share wheels", 10, -8)
	Text(t, "Export gives you text to paste to a friend (or another character). To import, paste it into the box and press Import. Links between wheels are not shared.", 20, -32, "GameFontHighlightSmall", 500)
	frame.shareBox = CreateFrame("EditBox", nil, t, "InputBoxTemplate")
	frame.shareBox:SetWidth(500)
	frame.shareBox:SetHeight(24)
	frame.shareBox:SetPoint("TOPLEFT", t, "TOPLEFT", 20, -86)
	frame.shareBox:SetAutoFocus(false)
	frame.shareBox:SetMaxLetters(0)
	frame.shareBox:SetScript("OnEscapePressed", function() frame.shareBox:ClearFocus() end)
	frame.shareBox:SetScript("OnTextChanged", function() pendingImport = nil end)
	frame.shareStatus = Text(t, "", 20, -170, "GameFontHighlightSmall", 500)
	local function status(msg) frame.shareStatus:SetText(msg or "") end

	Button(t, "Export this wheel", 20, -118, 130, function()
		local _, id = Cur()
		frame.shareBox:SetText(AW.ExportWheels({ id }))
		frame.shareBox:HighlightText()
		frame.shareBox:SetFocus()
		status("Wheel exported. Press Ctrl+C to copy it.")
	end)
	Button(t, "Export all wheels", 156, -118, 130, function()
		frame.shareBox:SetText(AW.ExportWheels())
		frame.shareBox:HighlightText()
		frame.shareBox:SetFocus()
		status("All wheels exported. Press Ctrl+C to copy it.")
	end)
	Button(t, "Import", 292, -118, 80, function()
		if Locked() then return end
		local text = frame.shareBox:GetText()
		local result, err = AW.PreviewImport(text)
		if not result then status("|cffff6060" .. err .. "|r") pendingImport = nil return end
		if #result.macros > 0 and pendingImport ~= text then
			-- macros run as if you wrote them: make the player look first
			pendingImport = text
			status("|cffffb030This import contains macros that run when you click them:|r\n" ..
				table.concat(result.macros, "\n", 1, math.min(#result.macros, 6)) ..
				"\nPress Import again to accept.")
			return
		end
		local ids = AW.CommitImport(result)
		pendingImport = nil
		if #ids > 0 then AW.P().current = ids[1] end
		AW.ApplyLayout()
		sel = 1
		RefreshAll()
		status("|cff60ff60Imported " .. #ids .. " wheel(s)." .. (#ids < #result.wheels and " (Wheel limit reached.)" or "") .. "|r")
	end)
end

---------------------------------------------------------------------------
-- frame and tabs
---------------------------------------------------------------------------
local function SelectTab(i)
	for k, t in ipairs(tabs) do
		if k == i then t:Show() else t:Hide() end
	end
	for k, b in ipairs(tabButtons) do
		if k == i then b:LockHighlight() else b:UnlockHighlight() end
	end
end

local function Build()
	frame = CreateFrame("Frame", "ActionWheelsConfig", UIParent)
	frame:SetWidth(580)
	frame:SetHeight(470)
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() frame:StartMoving() end)
	frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(frame)
	frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	frame.bg:SetVertexColor(0.05, 0.05, 0.09, 0.97)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
	title:SetText("ActionWheels")
	local x = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
	frame:Hide()
	tinsert(UISpecialFrames, "ActionWheelsConfig")

	local names = { "Wheels", "Settings", "Look", "Tracker", "Share" }
	local builders = { BuildWheelsTab, BuildSettingsTab, BuildLookTab, BuildTrackerTab, BuildShareTab }
	for i, n in ipairs(names) do
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetWidth(92)
		b:SetHeight(24)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (i - 1) * 96, -40)
		b:SetText(n)
		b:SetScript("OnClick", function() SelectTab(i) end)
		tabButtons[i] = b
		local t = CreateFrame("Frame", nil, frame)
		t:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -68)
		t:SetWidth(552)
		t:SetHeight(390)
		tabs[i] = t
		builders[i](t)
	end
end

AW.BuildConfig = function() Build() end
AW.ConfigFrame = function() return frame end
AW.SelectConfigTab = function(i) SelectTab(i) end

function AW.ConfigShown() return frame and frame:IsShown() or false end

function AW.RefreshConfig()
	if frame and frame:IsShown() then RefreshAll() end
end

function AW.HideConfig()
	if frame and frame:IsShown() then frame:Hide() end
end

function AW.ShowConfig()
	if AW.InCombat() then AW.Print("Settings are locked during combat.") return end
	if not frame then Build() end
	if frame:IsShown() then frame:Hide() return end
	RefreshAll()
	SelectTab(1)
	frame:Show()
end
