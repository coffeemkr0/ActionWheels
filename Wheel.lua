-- Wheel: the radial menu, built from secure frames so it opens and acts in combat.
--
-- Structure
--   ActionWheelsRoot            protected frame, shown/hidden/positioned by the toggle button
--     ActionWheelsCatcher       click outside the wheel to close it
--     ActionWheelsPage<k>       one protected page per wheel (only the current one is shown)
--       ActionWheelsP<k>S<i>    secure action buttons: spell / item / macro, or a sub-wheel link
--       prev / next / back      secure click buttons that switch pages
--
-- How combat works
--   * Everything that must happen in combat (open, close, switch page, run a slice) is done by
--     secure snippets or secure templates, which run in the restricted environment.
--   * Slot attributes, positions and icons change only out of combat. ApplyLayout() does that
--     and, called in combat, waits for PLAYER_REGEN_ENABLED.
--   * Cooldown / usable / range display is plain Lua and works in combat (it never touches
--     protected attributes).
ActionWheels = ActionWheels or {}
local AW = ActionWheels

local TEX = "Interface\\AddOns\\ActionWheels\\Textures\\"
local root, toggle, catcher, closeBtn
local BuildOpeners
local pages = {}      -- pages[k] = page frame; page k shows the k-th wheel of p.order
local pageOf = {}     -- wheel id -> page name, rebuilt by ApplyLayout
local nextBtn, prevBtn -- global secure buttons for the "next / previous wheel" key bindings

-- Snippet run by root (self = root): switch to page `name`; `push` remembers where we came from.
local GOPAGE = [[
	local name, push = ...
	local cur = self:GetAttribute("cur")
	if push and cur then self:SetAttribute("back_" .. name, cur) end
	if cur and cur ~= name then
		local c = self:GetFrameRef(cur)
		if c then c:Hide() end
	end
	local n = self:GetFrameRef(name)
	if n then
		n:Show()
		self:SetAttribute("cur", name)
		self:SetAttribute("last", name) -- "last wheel used", for the openers that ask for it
	end
]]

-- Click snippets for buttons that hold a "root" frame reference. DIR is replaced by next / prev.
local PAGE_CLICK = [[
	local r = self:GetFrameRef("root")
	if not r:IsShown() then return end
	local c = r:GetFrameRef(r:GetAttribute("cur"))
	local n = c and c:GetAttribute("DIR")
	if n then r:RunAttribute("gopage", n) end
]]
local BACK_CLICK = [[
	local r = self:GetFrameRef("root")
	local cur = r:GetAttribute("cur")
	r:RunAttribute("gopage", r:GetAttribute("back_" .. cur) or r:GetAttribute("home"))
]]

local function pageName(k) return "page" .. k end

local SOUND_NAMES = { hover = "igMainMenuOptionCheckBoxOn", use = "igMainMenuOptionCheckBoxOff" }
local SOUND_KITS = { hover = "IG_MAINMENU_OPTION_CHECKBOX_ON", use = "IG_MAINMENU_OPTION_CHECKBOX_OFF" }
function AW.Sound(kind)
	local S = ActionWheelsDB and ActionWheelsDB.profile and AW.P().settings
	if not (S and S.sounds and PlaySound) then return end
	pcall(PlaySound, (SOUNDKIT and SOUNDKIT[SOUND_KITS[kind]]) or SOUND_NAMES[kind])
end

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- A thin square border made of four edge textures. Behaves like one texture for SetVertexColor.
function AW.SquareBorder(parent, layer, thickness)
	local t = thickness or 2
	local e = {}
	local function edge(p1, p2, w, h)
		local tex = parent:CreateTexture(nil, layer or "BORDER")
		tex:SetTexture(WHITE)
		tex:SetPoint(p1, parent, p1, 0, 0)
		tex:SetPoint(p2, parent, p2, 0, 0)
		if w then tex:SetWidth(w) end
		if h then tex:SetHeight(h) end
		e[#e + 1] = tex
	end
	edge("TOPLEFT", "TOPRIGHT", nil, t)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, t)
	edge("TOPLEFT", "BOTTOMLEFT", t, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", t, nil)
	local border = {}
	function border:SetVertexColor(r, g, b, a)
		for _, tex in ipairs(e) do tex:SetVertexColor(r, g, b, a or 1) end
	end
	function border:Show() for _, tex in ipairs(e) do tex:Show() end end
	function border:Hide() for _, tex in ipairs(e) do tex:Hide() end end
	return border
end

local function Font(fs, size) fs:SetFont("Fonts\\ARIALN.TTF", size) end

local function SecureLabel(b, text)
	b.t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.t:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.t:SetText(text)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
	b.hl:SetVertexColor(0.3, 0.5, 1, 0.3)
end

local function HubButton(page, text, snippet)
	local b = CreateFrame("Button", nil, page, "SecureHandlerClickTemplate")
	b:SetFrameLevel(page:GetFrameLevel() + 3)
	b:SetWidth(22)
	b:SetHeight(18)
	b:RegisterForClicks("LeftButtonUp")
	b:SetFrameRef("root", root)
	b:SetAttribute("_onclick", snippet)
	SecureLabel(b, text)
	return b
end

local function BuildSlice(page, i)
	local b = CreateFrame("Button", "ActionWheelsP" .. page.k .. "S" .. i, page, "SecureActionButtonTemplate")
	b:SetFrameLevel(page:GetFrameLevel() + 2)
	-- Newer clients only run a secure action on the click event (down or up) that matches the
	-- "cast on key press" setting, so a button registered for one direction can silently do
	-- nothing. Register both and pin the action to the release so the setting doesn't matter.
	-- Left only: right-click is reserved for editing (not a secure action).
	b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	b:SetAttribute("useOnKeyDown", false)
	b.index, b.page = i, page
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetTexture(WHITE)
	b.bg:SetVertexColor(0.05, 0.05, 0.09, 0.92)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.icon:Hide()
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.cd:EnableMouse(false) -- never let the swirl swallow the click
	b.ring = AW.SquareBorder(b, "BORDER", 2)
	b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
	-- "checked" look of the built-in action bars: the game's own additive highlight over the icon
	b.glow = b:CreateTexture(nil, "ARTWORK", nil, 2)
	b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	b.glow:SetBlendMode("ADD")
	b.glow:Hide()
	b.hl = b:CreateTexture(nil, "OVERLAY")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture(WHITE)
	b.hl:SetVertexColor(0.2, 0.55, 1, 0.3)
	b.hl:Hide()
	-- press and click feedback: a dark "pushed" overlay while the mouse is down, a white flash on
	-- release, a green flash when the cast is confirmed (see AW.FlashSlice)
	b.push = b:CreateTexture(nil, "OVERLAY")
	b.push:SetAllPoints(b)
	b.push:SetTexture(WHITE)
	b.push:SetVertexColor(0, 0, 0, 0.5)
	b.push:Hide()
	b.flash = b:CreateTexture(nil, "OVERLAY", nil, 3)
	b.flash:SetAllPoints(b)
	b.flash:SetTexture(WHITE)
	b.flash:SetBlendMode("ADD")
	b.flash:Hide()
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 6)
	b:HookScript("OnEnter", function(self)
		self.hl:Show()
		AW.Sound("hover")
		AW.ShowSlotTooltip(self)
		local p = AW.P()
		local def = p.wheels[self.page.wheelId]
		self.page.name:SetText(AW.DescribeSlot(def and def.items[self.index]))
	end)
	b:HookScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self.push:Show() end
	end)
	b:HookScript("OnMouseUp", function(self, button)
		self.push:Hide()
		if button == "RightButton" then
			if AW.swap then AW.CancelSwap() else AW.ShowSlotMenu(self) end
		end
	end)
	b:HookScript("OnLeave", function(self)
		GameTooltip:Hide()
		self.push:Hide()
		self.hl:Hide()
		local p = AW.P()
		local def = p.wheels[self.page.wheelId]
		self.page.name:SetText(def and def.name or "")
	end)
	-- dropping a spell / item / macro from the cursor onto an open wheel fills the slice
	b:HookScript("OnReceiveDrag", function(self)
		AW.DropOnSlot(self.page.wheelId, self.index)
	end)
	b:HookScript("OnClick", function(self, button, down)
		if AW.swap then -- swap mode: slices are inert; a left-click picks where to move the slot
			if not down and button == "LeftButton" then AW.FinishSwap(self) end
			return
		end
		if AW.debug then
			AW.Print("slice " .. self.index .. " " .. tostring(button) .. (down and " down" or " up") ..
				": type=" .. tostring(self:GetAttribute("type")) .. " macro=" .. string.gsub(tostring(self:GetAttribute("macrotext")), "\n", " | ") ..
				" -> wheel " .. (root:IsShown() and "still open" or "closed"))
		end
		if not down then
			local def = AW.P().wheels[self.page.wheelId]
			local slot = def and def.items[self.index]
			AW.FlashSlice(self, 1, 1, 1) -- the click registered
			AW.Sound("use")
			local mode = AW.P().settings.closeMode
			if slot and slot.type == "spell" then
				-- remember which spell was clicked, to match the game's (possibly hidden) cast confirmation
				AW.NoteClick(slot.spell)
				if mode == "success" then AW.closeWatch = { name = slot.spell, t = GetTime(), slice = self } end
			end
			-- Plain-Lua close after the action, out of combat only (protected frames can't be hidden from
			-- Lua in combat; the macro's /click ActionWheelsClose line does that there). A spell slice in
			-- "success" mode closes when the cast is confirmed instead (State.lua / SliceConfirmed).
			local waitsForCast = mode == "success" and slot and slot.type == "spell"
			if mode ~= "never" and not waitsForCast and not self:GetAttribute("subwheel") and not InCombatLockdown() then
				root:Hide()
			end
		end
	end)
	return b
end

local function BuildPage(k)
	local page = CreateFrame("Frame", "ActionWheelsPage" .. k, root, "SecureHandlerBaseTemplate")
	page.k = k
	page:SetAllPoints(root)
	page:SetFrameLevel(root:GetFrameLevel() + 1)
	page:Hide()
	page.name = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	page.name:SetPoint("CENTER", page, "CENTER", 0, 20)
	page.name:SetWidth(84)
	page.num = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	page.num:SetPoint("CENTER", page, "CENTER", 0, -8)
	page.prev = HubButton(page, "<", (string.gsub(PAGE_CLICK, "DIR", "prev")))
	page.prev:SetPoint("CENTER", page, "CENTER", -26, -8)
	page.next = HubButton(page, ">", (string.gsub(PAGE_CLICK, "DIR", "next")))
	page.next:SetPoint("CENTER", page, "CENTER", 26, -8)
	page.back = HubButton(page, "back", BACK_CLICK)
	page.back:SetWidth(36)
	page.back:SetPoint("CENTER", page, "CENTER", 0, -28)
	page.slices = {}
	for i = 1, AW.MAXSLOTS do page.slices[i] = BuildSlice(page, i) end
	-- "/click ActionWheelsGo<k>" (from a sub-wheel slice's macro) switches to this page
	local go = CreateFrame("Button", "ActionWheelsGo" .. k, UIParent, "SecureHandlerClickTemplate")
	go:RegisterForClicks("AnyDown", "AnyUp")
	go:SetFrameRef("root", root)
	go:SetAttribute("_onclick", [[ local r = self:GetFrameRef("root"); if r:IsShown() then r:RunAttribute("gopage", "page]] .. k .. [[", true) end ]])
	-- let secure code find this page by name
	root:SetFrameRef(pageName(k), page)
	toggle:SetFrameRef(pageName(k), page)
	pages[k] = page
	return page
end

---------------------------------------------------------------------------
-- Tooltips: the game's own tooltip for spells and items; a short description for the rest
---------------------------------------------------------------------------
local function TooltipHasText()
	local n = GameTooltip:NumLines()
	return type(n) == "number" and n > 0
end

function AW.ShowSlotTooltip(b)
	local S = AW.P().settings
	if S.tooltips == false then return end
	local def = AW.P().wheels[b.page.wheelId]
	local slot = def and def.items[b.index]
	if AW.IsEmpty(slot) then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	local spec = slot
	if slot.type == "macro" then -- a macro with #showtooltip shows the tooltip of what it points at
		local v = AW.MacroTooltipSlot(slot.macrotext)
		if v then spec = v end
	end
	local shown = false
	if spec.type == "spell" then
		local id = AW.SpellIdOf and AW.SpellIdOf(spec.spell)
		if id and pcall(GameTooltip.SetSpellByID, GameTooltip, id) then shown = TooltipHasText() end
	elseif spec.type == "item" then
		local id = GetItemInfoInstant and (GetItemInfoInstant(spec.item))
		if id and pcall(GameTooltip.SetItemByID, GameTooltip, id) then shown = TooltipHasText() end
	end
	if not shown then
		GameTooltip:ClearLines()
		GameTooltip:AddLine(AW.DescribeSlot(slot), 1, 0.82, 0)
		if slot.type == "macro" then
			for line in string.gmatch(slot.macrotext or "", "[^\n]+") do
				if not string.find(line, "^%s*[#/]showtooltip") then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
			end
		elseif slot.type == "pet" then
			GameTooltip:AddLine("Pet command", 0.8, 0.8, 0.8)
		elseif slot.type == "wheel" then
			GameTooltip:AddLine("Opens another wheel", 0.8, 0.8, 0.8)
		elseif spec.type == "spell" then
			GameTooltip:AddLine("Spell", 0.8, 0.8, 0.8)
		elseif spec.type == "item" then
			GameTooltip:AddLine("Item", 0.8, 0.8, 0.8)
		end
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Right-click a slice: edit / swap / clear (out of combat only)
---------------------------------------------------------------------------
local slotMenu
function AW.HideSlotMenu()
	if slotMenu and slotMenu:IsShown() then slotMenu:Hide() end
end

function AW.CancelSwap()
	if not AW.swap then return end
	AW.swap = nil
	if not AW.InCombat() then AW.ApplyLayout() end
end

function AW.BeginSwap(slice)
	AW.swap = { wheelId = slice.page.wheelId, idx = slice.index }
	AW.ApplyLayout() -- slices go inert so a click only chooses the target
	AW.Print("Swap: left-click the slot to swap with (right-click to cancel).")
end

function AW.FinishSwap(slice)
	local sw = AW.swap
	AW.swap = nil
	if sw and slice.page.wheelId == sw.wheelId then
		AW.SwapSlots(AW.P(), sw.wheelId, sw.idx, slice.index)
	elseif sw then
		AW.Print("A slot can only be swapped within its own wheel.")
	end
	AW.ApplyLayout()
	if AW.RefreshConfig then AW.RefreshConfig() end
end

function AW.ShowSlotMenu(slice)
	if AW.InCombat() then AW.Print("Editing is locked during combat.") return end
	if not slotMenu then
		slotMenu = CreateFrame("Frame", "ActionWheelsSlotMenu", UIParent)
		slotMenu:SetFrameStrata("FULLSCREEN_DIALOG")
		slotMenu:SetWidth(190)
		slotMenu:SetHeight(76)
		slotMenu.bg = slotMenu:CreateTexture(nil, "BACKGROUND")
		slotMenu.bg:SetAllPoints(slotMenu)
		slotMenu.bg:SetTexture(WHITE)
		slotMenu.bg:SetVertexColor(0.05, 0.05, 0.09, 0.97)
		slotMenu:Hide()
		local function item(i, text, fn)
			local b = CreateFrame("Button", nil, slotMenu)
			b:SetWidth(190)
			b:SetHeight(22)
			b:SetPoint("TOPLEFT", slotMenu, "TOPLEFT", 0, -6 - (i - 1) * 22)
			b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.t:SetPoint("LEFT", b, "LEFT", 10, 0)
			b.t:SetText(text)
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints(b)
			b.hl:SetTexture(WHITE)
			b.hl:SetVertexColor(0.3, 0.5, 1, 0.3)
			b:SetScript("OnClick", function() slotMenu:Hide(); fn(slotMenu.slice) end)
		end
		item(1, "Edit slot...", function(s)
			local id, idx = s.page.wheelId, s.index
			AW.CloseWheel()
			if AW.EditSlot then AW.EditSlot(id, idx) end
		end)
		item(2, "Swap with another slot...", function(s) AW.BeginSwap(s) end)
		item(3, "Clear slot", function(s)
			local def = AW.P().wheels[s.page.wheelId]
			if def then def.items[s.index] = nil end
			AW.ApplyLayout()
			if AW.RefreshConfig then AW.RefreshConfig() end
		end)
	end
	slotMenu.slice = slice
	slotMenu:ClearAllPoints()
	local es = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	slotMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / es + 6, y / es - 6)
	slotMenu:Show()
end

---------------------------------------------------------------------------
-- Mouse openers: click a button to open / close the wheel, no keyboard needed.
--   Invisible secure buttons, for macros on action bars (see AW.MakeActionBarMacro):
--     /click ActionWheelsOpen        the wheel that opens first
--     /click ActionWheelsOpenLast    the last wheel you used
--     /click ActionWheelsOpen2       the 2nd wheel directly (...1 to 8)
--   Visible on-screen buttons, movable with Shift + drag:
--     ActionWheelsLauncher           opens the last wheel used
--     ActionWheelsLauncher<k>        one optional button per wheel (opens that wheel)
-- All are secure click handlers, so they work in combat. Unlike the key they always toggle: a
-- click opens, clicking outside the wheel (or the opener again) closes.
---------------------------------------------------------------------------
local OPEN_SNIPPET = [[
	-- A real mouse click arrives as press then release; a macro's /click may arrive as a single press
	-- or a single release, depending on the client. Act once per click either way: an event that
	-- directly follows its opposite is the second half of a pair and is ignored.
	local dir = (down == true) and "d" or "u"
	local opp = (dir == "d") and "u" or "d"
	if self:GetAttribute("lastev") == opp then
		self:SetAttribute("lastev", nil)
		return
	end
	self:SetAttribute("lastev", dir)
	local w = self:GetFrameRef("wheel")
	if w:IsShown() then w:Hide() return end
	local target = self:GetAttribute("target")
	if target == "last" then target = w:GetAttribute("last") end
	w:RunAttribute("gopage", target or w:GetAttribute("home"))
	w:ClearAllPoints()
	if self:GetAttribute("at") == "center" then
		w:SetPoint("CENTER", "$parent", "CENTER", 0, 0)
	else
		w:SetPoint("CENTER", "$cursor")
	end
	w:Show()
]]
local openers = {}
local launchers = {} -- launchers.last and launchers[k]

local function MakeOpener(name, target)
	local b = CreateFrame("Button", name, UIParent, "SecureHandlerClickTemplate")
	b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	b:SetFrameRef("wheel", root)
	b:SetAttribute("target", target)
	b:SetAttribute("at", "cursor")
	b:SetAttribute("_onclick", OPEN_SNIPPET)
	b.isLauncher = false
	openers[#openers + 1] = b
	return b
end

-- The saved settings a launcher button uses: { show / hide, x, y }. "last" lives in the account
-- settings; the button for wheel k belongs to that wheel (so it follows the wheel if wheels move).
function AW.LauncherData(b, create)
	if b.key == "last" then return ActionWheelsDB and ActionWheelsDB.launcher end
	local p = AW.P()
	local w = p.wheels[p.order[b.key] or ""]
	if not w then return nil end
	if create and not w.launcher then w.launcher = {} end
	return w.launcher
end

local function BuildLauncher(name, target, key)
	local b = MakeOpener(name, target)
	b.key = key
	b.isLauncher = true -- an on-screen button (follows "opens at"); the plain openers are for action bars
	b:SetWidth(44)
	b:SetHeight(44)
	b:SetFrameStrata("MEDIUM")
	b:SetMovable(true)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	b:Hide()
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetTexture(WHITE)
	b.bg:SetVertexColor(0.05, 0.05, 0.09, 0.92)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 4)
	b.icon:SetWidth(26)
	b.icon:SetHeight(26)
	b.icon:SetTexture(TEX .. "MinimapIcon")
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
	b.label:SetWidth(42)
	b.label:SetHeight(10)
	b.label:SetText(key == "last" and "Last" or "")
	b.border = AW.SquareBorder(b, "BORDER", 2)
	b.border:SetVertexColor(0.4, 0.45, 0.55, 1)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture(WHITE)
	b.hl:SetVertexColor(0.2, 0.55, 1, 0.3)
	-- Shift + drag moves it (out of combat, unless locked)
	b:SetScript("OnDragStart", function(self)
		local L = ActionWheelsDB and ActionWheelsDB.launcher
		if IsShiftKeyDown() and L and not L.locked and not InCombatLockdown() then
			self.moving = true
			self:StartMoving()
		end
	end)
	b:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = false
		self:StopMovingOrSizing()
		local d = AW.LauncherData(self, true)
		if d then d.x, d.y = self:GetCenter() end
		AW.PlaceLaunchers()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("ActionWheels", 1, 0.82, 0)
		GameTooltip:AddLine(self.key == "last" and "Click: open the last wheel you used" or "Click: open this wheel", 1, 1, 1)
		GameTooltip:AddLine("Shift + drag: move this button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

BuildOpeners = function()
	MakeOpener("ActionWheelsOpen", nil)
	MakeOpener("ActionWheelsOpenLast", "last")
	for k = 1, AW.MAXWHEELS do MakeOpener("ActionWheelsOpen" .. k, "page" .. k) end
	launchers.last = BuildLauncher("ActionWheelsLauncher", "last", "last")
	for k = 1, AW.MAXWHEELS do launchers[k] = BuildLauncher("ActionWheelsLauncher" .. k, "page" .. k, k) end
end

-- Position and visibility of every launcher button. Out of combat only (they are protected).
function AW.PlaceLaunchers()
	if not (launchers.last and ActionWheelsDB and ActionWheelsDB.profile) or InCombatLockdown() then return end
	local function place(b, d, slot)
		b:ClearAllPoints()
		if d and d.x and d.y then b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", d.x, d.y)
		else b:SetPoint("CENTER", UIParent, "CENTER", -150 + slot * 48, -200) end
	end
	local L = ActionWheelsDB.launcher
	place(launchers.last, L, 0)
	if L.hide then launchers.last:Hide() else launchers.last:Show() end
	local p = AW.P()
	for k = 1, AW.MAXWHEELS do
		local b = launchers[k]
		local id = p.order[k]
		local w = id and p.wheels[id]
		local d = w and w.launcher
		if w and d and d.show then
			place(b, d, k)
			b.label:SetText(string.sub(w.name, 1, 8))
			b:Show()
		else
			b:Hide()
		end
	end
end
AW.PlaceLauncher = AW.PlaceLaunchers

local function Build()
	root = CreateFrame("Frame", "ActionWheelsRoot", UIParent, "SecureHandlerStateTemplate")
	root:SetFrameStrata("DIALOG")
	root:SetWidth(96)
	root:SetHeight(96)
	root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	root:Hide()
	root:SetAttribute("gopage", GOPAGE)
	-- "auto" wheels: a state driver keeps `home` (the page that opens first) in step with the game
	root:SetAttribute("_onstate-autopage", [[ self:SetAttribute("home", newstate) ]])
	-- "auto" key behaviour: hold in combat, press-to-toggle out of combat. The state driver keeps
	-- root's `combatmode` attribute in step with the game; the toggle button reads it on each press.
	root:SetAttribute("combatmode", "toggle")
	root:SetAttribute("_onstate-combatmode", [[ self:SetAttribute("combatmode", newstate) ]])
	RegisterStateDriver(root, "combatmode", "[combat] hold; toggle")

	-- click anywhere outside the wheel to close it
	catcher = CreateFrame("Button", "ActionWheelsCatcher", root, "SecureHandlerClickTemplate,SecureHandlerMouseWheelTemplate")
	catcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	catcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	catcher:SetFrameLevel(root:GetFrameLevel())
	catcher:RegisterForClicks("AnyUp")
	catcher:SetFrameRef("wheel", root)
	catcher:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])
	-- scrolling the mouse wheel anywhere while the wheel is open switches wheel (scroll up = previous)
	catcher:EnableMouseWheel(true)
	catcher:SetAttribute("_onmousewheel", [[
		local r = self:GetFrameRef("wheel")
		if r:GetAttribute("wheelscroll") ~= 1 then return end
		local c = r:GetFrameRef(r:GetAttribute("cur"))
		if not c then return end
		local up = delta > 0
		if r:GetAttribute("wheelrev") == 1 then up = not up end
		local n = c:GetAttribute(up and "prev" or "next")
		if n then r:RunAttribute("gopage", n) end
	]])

	-- Target of the "/click ActionWheelsClose" line every slice's macro ends with. A secure macro may
	-- /click a secure handler in combat, which is how a slice closes the wheel after it ran.
	closeBtn = CreateFrame("Button", "ActionWheelsClose", UIParent, "SecureHandlerClickTemplate")
	closeBtn:RegisterForClicks("AnyDown", "AnyUp")
	closeBtn:SetFrameRef("wheel", root)
	closeBtn:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])

	root.hubBg = root:CreateTexture(nil, "BACKGROUND")
	root.hubBg:SetTexture(TEX .. "Circle")
	root.hubBg:SetVertexColor(0.04, 0.04, 0.08, 0.9)
	root.hubBg:SetPoint("CENTER", root, "CENTER", 0, 0)
	root.hubBg:SetWidth(96)
	root.hubBg:SetHeight(96)

	toggle = CreateFrame("Button", "ActionWheelsToggle", UIParent, "SecureHandlerClickTemplate")
	toggle:RegisterForClicks("AnyDown", "AnyUp")
	toggle:SetFrameRef("wheel", root)
	toggle:SetAttribute("mode", "toggle")
	toggle:SetAttribute("at", "cursor")
	toggle:SetAttribute("_onclick", [[
		local w = self:GetFrameRef("wheel")
		local show
		local mode = self:GetAttribute("mode")
		if mode == "auto" then mode = w:GetAttribute("combatmode") end
		if mode == "hold" then
			show = down and true or false
		else
			if not down then return end
			show = not w:IsShown()
		end
		if show then
			-- open on the wheel that opens first, or on the last one used (unless an auto condition applies)
			local target = w:GetAttribute("home")
			if self:GetAttribute("first") == "last" and target == w:GetAttribute("defhome") then
				target = w:GetAttribute("last") or target
			end
			w:RunAttribute("gopage", target)
			w:ClearAllPoints()
			if self:GetAttribute("at") == "center" then
				w:SetPoint("CENTER", "$parent", "CENTER", 0, 0)
			else
				w:SetPoint("CENTER", "$cursor")
			end
			w:Show()
		else
			w:Hide()
		end
	]])

	BuildOpeners()

	-- key-bindable next / previous wheel (they do nothing while the wheel is closed)
	nextBtn = CreateFrame("Button", "ActionWheelsNext", UIParent, "SecureHandlerClickTemplate")
	nextBtn:RegisterForClicks("AnyDown")
	nextBtn:SetFrameRef("root", root)
	nextBtn:SetAttribute("_onclick", (string.gsub(PAGE_CLICK, "DIR", "next")))
	prevBtn = CreateFrame("Button", "ActionWheelsPrev", UIParent, "SecureHandlerClickTemplate")
	prevBtn:RegisterForClicks("AnyDown")
	prevBtn:SetFrameRef("root", root)
	prevBtn:SetAttribute("_onclick", (string.gsub(PAGE_CLICK, "DIR", "prev")))

	-- keep the slice faces live while the wheel is open
	local acc = 0
	root:SetScript("OnUpdate", function(_, dt)
		AW.AnimateFlashes()
		acc = acc + (dt or 0)
		if acc >= 0.1 then acc = 0; AW.RefreshStates() end
	end)
	root:SetScript("OnShow", function() AW.RefreshStates() end)
	root:SetScript("OnHide", function()
		GameTooltip:Hide()
		AW.HideSlotMenu()
		AW.CancelSwap()
	end)
end

---------------------------------------------------------------------------
-- Click feedback and closing
---------------------------------------------------------------------------
AW.flashing = {}
local FLASH_TIME = 0.4

function AW.FlashSlice(b, r, g, bl)
	if not (b and b.flash) then return end
	b.flash:SetVertexColor(r, g, bl)
	b.flashT = GetTime()
	b.flash:SetAlpha(0.8)
	b.flash:Show()
	AW.flashing[b] = true
end

function AW.AnimateFlashes()
	if next(AW.flashing) == nil then return end
	local now = GetTime()
	for b in pairs(AW.flashing) do
		local a = 1 - (now - (b.flashT or 0)) / FLASH_TIME
		if a <= 0 then
			b.flash:Hide()
			AW.flashing[b] = nil
		else
			b.flash:SetAlpha(a * 0.8)
		end
	end
end

-- The cast we were waiting for went off: flash the slice green; close the wheel unless in combat
-- (Lua can't hide it there - it stays open, close it with your key or by clicking outside).
function AW.SliceConfirmed(b)
	AW.FlashSlice(b, 0.3, 1, 0.4)
	if not InCombatLockdown() and root then root:Hide() end
end

function AW.CloseWheel()
	if root and not InCombatLockdown() then root:Hide() end
end

function AW.BuildWheel()
	if root then return end
	Build()
end

---------------------------------------------------------------------------
-- Live state: cooldown swirl, charges / item count, usable and range tinting
---------------------------------------------------------------------------
local lastPaintError
local function partOK(what, ok, err)
	if ok then return end
	if AW.debug and err ~= lastPaintError then
		lastPaintError = err
		AW.Print("slice display problem (" .. what .. "): " .. tostring(err))
	end
end

local function PaintCooldown(b, st)
	if st.cdSecret then
		-- Secret numbers can't be compared or (reliably) passed to SetCooldown. The game's duration
		-- object can be handed to the swirl; it is re-applied on each refresh (and clears at zero).
		if st.cdObject and b.cd.SetCooldownFromDurationObject then
			b.cd:SetCooldownFromDurationObject(st.cdObject, true)
		else
			b.cd:SetCooldown(st.cdStart, st.cdDur)
		end
		b.cdStart, b.cdDur = true, true
	elseif st.cdStart and st.cdDur and st.cdDur > 0 then
		if b.cdStart ~= st.cdStart or b.cdDur ~= st.cdDur then
			b.cd:SetCooldown(st.cdStart, st.cdDur)
			b.cdStart, b.cdDur = st.cdStart, st.cdDur
		end
	elseif b.cdStart then
		b.cd:SetCooldown(0, 0)
		b.cdStart, b.cdDur = nil, nil
	end
end

local function PaintCount(b, st)
	if st.count then b.count:SetText(st.count) else b.count:SetText("") end
end

local function Paint(b, slot)
	if AW.swap then -- swap mode: the chosen slot is green, the rest orange
		local src = (b.page.wheelId == AW.swap.wheelId and b.index == AW.swap.idx)
		if src then b.ring:SetVertexColor(0.3, 1, 0.3, 1) else b.ring:SetVertexColor(1, 0.65, 0.1, 1) end
		return
	end
	-- a macro with #showtooltip shows (and tracks) the spell or item it points at; the target can
	-- change while the wheel is open ([mod:shift] etc.), so the icon is re-checked every refresh
	if slot.type == "macro" then
		local v = AW.MacroTooltipSlot(slot.macrotext)
		if not v then return end
		local tex = AW.SlotIcon(slot)
		if tex and b.iconTex ~= tex then b.icon:SetTexture(tex); b.iconTex = tex end
		slot = v
	end
	local st = AW.SlotState(slot)
	-- spell / item slices follow the live icon (a transformed spell changes it), like action bars do;
	-- while the spell is active they show the icon the bar shows for it (learned, see State.lua)
	if (slot.type == "spell" or slot.type == "item") and not (slot.icon and slot.icon ~= "") then
		local ok, tex = pcall(AW.SlotIcon, slot)
		if ok and slot.type == "spell" and st.active then
			local a = AW.ActiveIcon(slot.spell)
			if a then tex = a end
		end
		if ok and tex ~= nil and not (issecretvalue and issecretvalue(tex)) and b.iconTex ~= tex then
			b.icon:SetTexture(tex)
			b.iconTex = tex
		end
	end
	-- The look of a slice is applied in order of importance, each part on its own: if the game
	-- refuses one of the later parts in combat (cooldown numbers, counts), the highlight and tint
	-- above it must still be correct. (A failure used to leave a stale gold ring on the wrong slice.)
	-- buff on you (the active Aspect, etc.): gold frame plus the action bar's checked highlight
	if st.active then
		b.ring:SetVertexColor(1, 0.82, 0.1, 1)
		b.glow:Show()
	else
		local base = b.baseRing or { 0.4, 0.45, 0.55 }
		b.ring:SetVertexColor(base[1], base[2], base[3], 1)
		b.glow:Hide()
	end
	local r, g, bl, desat = AW.StateTint(st)
	b.icon:SetVertexColor(r, g, bl)
	if b.icon.SetDesaturated then b.icon:SetDesaturated(desat) end
	partOK("cooldown", pcall(PaintCooldown, b, st))
	partOK("count", pcall(PaintCount, b, st))
end

function AW.RefreshStates()
	if not (root and ActionWheelsDB and ActionWheelsDB.profile) then return end
	local p = AW.P()
	for _, page in pairs(pages) do
		if page:IsShown() and page.wheelId then
			local def = p.wheels[page.wheelId]
			if def then
				for i = 1, def.slots do
					local slot = def.items[i]
					if not AW.IsEmpty(slot) and slot.type ~= "pet" and slot.type ~= "wheel" then
						-- never let a display problem become an error message
						partOK("slice " .. i, pcall(Paint, page.slices[i], slot))
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Layout: push the profile onto the secure frames. Out of combat only; otherwise deferred.
---------------------------------------------------------------------------
local function LayoutPage(page, id, k, count, targets)
	local p = AW.P()
	local S = p.settings
	local def = p.wheels[id]
	local n = def.slots
	local btn = S.buttonSize or 56
	-- square buttons: keep the hub clear, and neighbours (even at the diagonal) from overlapping
	local fs, hs = S.fontScale or 1, S.hubScale or 1
	local minR = math.max(48 * hs + btn / 2 + 8, 1.15 * btn / (2 * math.sin(math.pi / n)))
	local radius = math.max(S.radius or 105, minR)

	-- centre hub: text and controls scale with the "text size" and "centre size" settings
	root:SetWidth(96 * hs)
	root:SetHeight(96 * hs)
	root.hubBg:SetWidth(96 * hs)
	root.hubBg:SetHeight(96 * hs)
	page.name:SetFont("Fonts\\ARIALN.TTF", 12 * fs)
	page.name:SetWidth(84 * hs)
	page.name:ClearAllPoints()
	page.name:SetPoint("CENTER", page, "CENTER", 0, 20 * hs)
	page.num:SetFont("Fonts\\ARIALN.TTF", 10 * fs)
	page.num:ClearAllPoints()
	page.num:SetPoint("CENTER", page, "CENTER", 0, -8 * hs)
	for _, hb in ipairs({ page.prev, page.next, page.back }) do
		hb:SetHeight(18 * hs)
		hb.t:SetFont("Fonts\\ARIALN.TTF", 12 * fs)
	end
	page.prev:SetWidth(22 * hs)
	page.next:SetWidth(22 * hs)
	page.back:SetWidth(36 * hs)
	page.prev:ClearAllPoints()
	page.prev:SetPoint("CENTER", page, "CENTER", -26 * hs, -8 * hs)
	page.next:ClearAllPoints()
	page.next:SetPoint("CENTER", page, "CENTER", 26 * hs, -8 * hs)
	page.back:ClearAllPoints()
	page.back:SetPoint("CENTER", page, "CENTER", 0, -28 * hs)

	page.wheelId = id
	page.name:SetText(def.name)
	page:SetAttribute("next", pageName(k % count + 1))
	page:SetAttribute("prev", pageName((k - 2) % count + 1))
	page.num:SetText(count > 1 and (k .. "/" .. count) or "")
	if count > 1 then page.prev:Show(); page.next:Show() else page.prev:Hide(); page.next:Hide() end
	if targets[id] then page.back:Show() else page.back:Hide() end

	local step = 2 * math.pi / n
	for i = 1, AW.MAXSLOTS do
		local b = page.slices[i]
		for _, key in ipairs(AW.ATTR_KEYS) do b:SetAttribute(key, nil) end
		b:SetAttribute("subwheel", nil)
		b.cdStart, b.cdDur = nil, nil
		b.glow:Hide()
		b.cd:SetCooldown(0, 0)
		b.count:SetFont("Fonts\\ARIALN.TTF", 14 * fs, "OUTLINE")
		b.count:SetText("")
		b.baseRing = { 0.4, 0.45, 0.55 }
		b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
		if i <= n then
			local slot = def.items[i]
			local cr, cg, cb = AW.SlotColor(slot) -- the slot's own border colour
			if cr then
				b.baseRing = { cr, cg, cb }
				b.ring:SetVertexColor(cr, cg, cb, 1)
			end
			if slot and slot.type == "wheel" and not pageOf[slot.wheel] then slot = nil end -- dangling link
			if slot and slot.type == "wheel" then
				b:SetAttribute("subwheel", pageOf[slot.wheel])
				-- the page name is "page<k>": switch with /click ActionWheelsGo<k>
				if not AW.swap then
					for key, v in pairs(AW.SecureAttributes(slot, string.match(pageOf[slot.wheel], "%d+"))) do b:SetAttribute(key, v) end
				end
			elseif not AW.swap then -- (in swap mode the slices stay inert: a click only chooses the target)
				for key, v in pairs(AW.SecureAttributes(slot, nil, S.closeMode)) do b:SetAttribute(key, v) end
			end
			b:SetWidth(btn)
			b:SetHeight(btn)
			b.icon:SetWidth(btn - 6)
			b.icon:SetHeight(btn - 6)
			b.glow:SetWidth(btn + 2)
			b.glow:SetHeight(btn + 2)
			b.cd:SetWidth(btn - 6)
			b.cd:SetHeight(btn - 6)
			local a = (i - 1) * step -- clockwise from the top
			b:ClearAllPoints()
			b:SetPoint("CENTER", page, "CENTER", math.sin(a) * radius, math.cos(a) * radius)
			local icon = AW.SlotIcon(slot)
			b.iconTex = icon
			if icon then
				b.icon:SetTexture(icon)
				b.icon:SetVertexColor(1, 1, 1)
				b.icon:Show()
			else
				b.icon:Hide()
			end
			b:Show()
		else
			b:Hide()
		end
	end
end

function AW.ApplyLayout()
	if not root then return false end
	if AW.InCombat() then
		AW.pendingApply = true
		return false
	end
	AW.pendingApply = false
	local p = AW.P()
	local S = p.settings
	local count = #p.order

	root:SetScale(S.scale or 1)
	toggle:SetAttribute("mode", S.openMode or "toggle")
	toggle:SetAttribute("at", S.openAt or "cursor")
	toggle:SetAttribute("first", S.openFirst or "selected")
	root:SetAttribute("wheelscroll", S.wheelScroll and 1 or 0)
	root:SetAttribute("wheelrev", S.wheelReverse and 1 or 0)
	catcher:EnableMouseWheel(S.wheelScroll and true or false) -- off: the wheel passes through (camera zoom)
	-- on-screen buttons follow "opens at"; action bar macros default to the screen centre
	for _, o in ipairs(openers) do
		o:SetAttribute("at", o.isLauncher and (S.openAt or "cursor") or (S.barOpenAt or "center"))
	end
	AW.PlaceLaunchers()

	-- wheel id -> page, and which wheels some slot links to (those get a "back" button)
	pageOf = {}
	for k, id in ipairs(p.order) do pageOf[id] = pageName(k) end
	local targets = {}
	for _, w in pairs(p.wheels) do
		for _, slot in pairs(w.items) do
			if slot.type == "wheel" then targets[slot.wheel] = true end
		end
	end

	for k, id in ipairs(p.order) do
		local page = pages[k] or BuildPage(k)
		LayoutPage(page, id, k, count, targets)
	end
	for k, page in pairs(pages) do
		if k > count then page.wheelId = nil; page:Hide() end
	end

	if AW.TrackerRefresh then AW.TrackerRefresh() end -- slots / wheels changed: re-pick the tracked spells
	-- the wheel being edited opens first, unless an "auto" condition of another wheel holds
	local home = pageOf[p.current] or pageName(1)
	local clauses = {}
	for k, id in ipairs(p.order) do
		local cond = p.wheels[id].auto
		if cond and AW.ValidCondition(cond) then clauses[#clauses + 1] = cond .. " " .. pageName(k) end
	end
	root:SetAttribute("defhome", home) -- the wheel that opens first when no auto condition applies
	root:SetAttribute("home", home)
	root:SetAttribute("cur", home)
	if #clauses > 0 then
		clauses[#clauses + 1] = home
		RegisterStateDriver(root, "autopage", table.concat(clauses, "; "))
	else
		UnregisterStateDriver(root, "autopage")
	end
	for k, page in pairs(pages) do
		if k <= count and pageName(k) == home then page:Show() else page:Hide() end
	end
	return true
end
