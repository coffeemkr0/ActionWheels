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

local function Edit(parent, x, y, w, onEnter)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetWidth(w)
	e:SetHeight(20)
	e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function() e:ClearFocus() end)
	if onEnter then e:SetScript("OnEnterPressed", function() onEnter(e:GetText()); e:ClearFocus() end) end
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
	end)
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
	end)
	Text(t, "e.g. [mounted]  [combat]  [stance:1]", 358, -38, "GameFontDisableSmall")

	-- preview ring
	frame.ring = CreateFrame("Frame", nil, t)
	frame.ring:SetWidth(10)
	frame.ring:SetHeight(10)
	frame.ring:SetPoint("TOPLEFT", t, "TOPLEFT", 150, -205)
	for i = 1, AW.MAXSLOTS do
		local b = CreateFrame("Button", nil, t)
		b:SetWidth(46)
		b:SetHeight(46)
		b:RegisterForClicks("LeftButtonUp")
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints(b)
		b.bg:SetTexture("Interface\\AddOns\\ActionWheels\\Textures\\Circle")
		b.bg:SetVertexColor(0.07, 0.07, 0.11, 0.95)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetWidth(34)
		b.icon:SetHeight(34)
		b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.ring = b:CreateTexture(nil, "OVERLAY")
		b.ring:SetAllPoints(b)
		b.ring:SetTexture("Interface\\AddOns\\ActionWheels\\Textures\\Ring")
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
	local hint = Text(t, "Drag a spell, item or macro onto a slot, or pick a slot and fill in the form.", 4, -352, "GameFontHighlightSmall", 280)

	-- slot form
	frame.slotTitle = Text(t, "Slot 1", 310, -70, "GameFontNormal", 240)
	frame.kindButtons = {}
	for i, k in ipairs(KINDS) do
		local b = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
		b:SetWidth(46)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", t, "TOPLEFT", 310 + (i - 1) * 48, -96)
		b:SetText(k[2])
		b:SetScript("OnClick", function() formKind = k[1]; LoadForm() end)
		frame.kindButtons[i] = b
	end
	Text(t, "Value", 310, -126, "GameFontNormalSmall")
	frame.valueBox = Edit(t, 310, -142, 230)
	frame.valueBox:SetMaxLetters(255)
	frame.hint = Text(t, "", 310, -168, "GameFontHighlightSmall", 236)
	Text(t, "Label (optional)", 310, -214, "GameFontNormalSmall")
	frame.labelBox = Edit(t, 310, -230, 110)
	frame.labelBox:SetMaxLetters(24)
	Text(t, "Icon (optional)", 430, -214, "GameFontNormalSmall")
	frame.iconBox = Edit(t, 430, -230, 110)
	Button(t, "Save slot", 310, -264, 100, SaveForm)
	Button(t, "Clear slot", 416, -264, 100, function()
		if Locked() then return end
		local _, _, def = Cur()
		def.items[sel] = nil
		frame.status:SetText("")
		AW.ApplyLayout(); RefreshWheels()
	end)
	frame.status = Text(t, "", 310, -296, "GameFontHighlightSmall", 236)
	refreshers[#refreshers + 1] = RefreshWheels
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
local function BuildSettingsTab(t)
	Text(t, "How the wheel opens", 10, -8)
	Cycle(t, "Key behaviour", 20, -32, { { "toggle", "Press to open / close" }, { "hold", "Hold to show" } },
		function() return S().openMode end, function(v) S().openMode = v end, 190, 140)
	Cycle(t, "Opens at", 20, -62, { { "cursor", "The mouse cursor" }, { "center", "Screen centre" } },
		function() return S().openAt end, function(v) S().openAt = v end, 190, 140)
	Text(t, "Look", 10, -104)
	Slider(t, "Button size", 20, -136, 40, 110, 1, function() return S().buttonSize end, function(v) S().buttonSize = v end)
	Slider(t, "Minimum ring radius", 20, -176, 70, 200, 1, function() return S().radius end, function(v) S().radius = v end)
	Slider(t, "Whole wheel scale", 20, -216, 0.6, 2, 0.05, function() return S().scale end, function(v) S().scale = v end, "%.2f")
	Text(t, "Other", 280, -104)
	Check(t, "Show the minimap button", 276, -128,
		function() return not ActionWheelsDB.minimap.hide end,
		function(v) ActionWheelsDB.minimap.hide = not v; AW.UpdateMinimap() end)
	Check(t, "Separate wheels for this character", 276, -156,
		function() return AW.UsingCharProfile() end,
		function(v)
			if Locked() then return end
			AW.SetCharProfile(v)
			AW.ApplyLayout()
			sel = 1
			RefreshAll()
		end)
	Button(t, "Key bindings...", 280, -196, 140, function() AW.OpenKeyBindings() end)
	local reset = Button(t, "Restore starter wheel", 280, -226, 160, nil)
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
	Text(t, "Wheels edited in the Wheels tab. Key: Esc > Key Bindings > AddOns > ActionWheels.", 10, -268, "GameFontHighlightSmall", 500)
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

	local names = { "Wheels", "Settings", "Share" }
	local builders = { BuildWheelsTab, BuildSettingsTab, BuildShareTab }
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
