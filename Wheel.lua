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
	b.bg:SetTexture(TEX .. "Circle")
	b.bg:SetVertexColor(0.07, 0.07, 0.11, 0.92)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.icon:Hide()
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.cd:EnableMouse(false) -- never let the swirl swallow the click
	b.ring = b:CreateTexture(nil, "BORDER")
	b.ring:SetAllPoints(b)
	b.ring:SetTexture(TEX .. "Ring")
	b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
	b.glow = b:CreateTexture(nil, "ARTWORK", nil, 2)
	b.glow:SetAllPoints(b)
	b.glow:SetTexture(TEX .. "Circle")
	b.glow:SetVertexColor(0.3, 1, 0.45, 0.28)
	b.glow:Hide()
	b.hl = b:CreateTexture(nil, "OVERLAY")
	b.hl:SetAllPoints(b)
	b.hl:SetTexture(TEX .. "Circle")
	b.hl:SetVertexColor(0.2, 0.55, 1, 0.45)
	b.hl:Hide()
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 6)
	b:HookScript("OnEnter", function(self)
		self.hl:Show()
		local p = AW.P()
		local def = p.wheels[self.page.wheelId]
		self.page.name:SetText(AW.DescribeSlot(def and def.items[self.index]))
	end)
	b:HookScript("OnLeave", function(self)
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
		if AW.debug then
			AW.Print("slice " .. self.index .. " " .. tostring(button) .. (down and " down" or " up") ..
				": type=" .. tostring(self:GetAttribute("type")) .. " macro=" .. string.gsub(tostring(self:GetAttribute("macrotext")), "\n", " | ") ..
				" -> wheel " .. (root:IsShown() and "still open" or "closed"))
		end
		-- remember which spell was clicked, to match the game's (possibly hidden) cast confirmation
		if not down then
			local def = AW.P().wheels[self.page.wheelId]
			local slot = def and def.items[self.index]
			if slot and slot.type == "spell" then AW.NoteClick(slot.spell) end
		end
		-- Plain-Lua close, runs after the action. Protected frames may only be hidden from Lua out of
		-- combat; in combat the secure snippet below has to do it (or press the key again).
		if not down and not self:GetAttribute("subwheel") and not InCombatLockdown() then
			root:Hide()
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

	-- click anywhere outside the wheel to close it
	catcher = CreateFrame("Button", "ActionWheelsCatcher", root, "SecureHandlerClickTemplate")
	catcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	catcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	catcher:SetFrameLevel(root:GetFrameLevel())
	catcher:RegisterForClicks("AnyUp")
	catcher:SetFrameRef("wheel", root)
	catcher:SetAttribute("_onclick", [[ self:GetFrameRef("wheel"):Hide() ]])

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
		if self:GetAttribute("mode") == "hold" then
			show = down and true or false
		else
			if not down then return end
			show = not w:IsShown()
		end
		if show then
			w:RunAttribute("gopage", w:GetAttribute("home")) -- always open on the first wheel
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
		acc = acc + (dt or 0)
		if acc >= 0.1 then acc = 0; AW.RefreshStates() end
	end)
	root:SetScript("OnShow", function() AW.RefreshStates() end)
end

function AW.BuildWheel()
	if root then return end
	Build()
end

---------------------------------------------------------------------------
-- Live state: cooldown swirl, charges / item count, usable and range tinting
---------------------------------------------------------------------------
local function Paint(b, slot)
	local st = AW.SlotState(slot)
	if st.cdSecret then
		-- secret numbers: no comparing, just hand them to the swirl each refresh
		b.cd:SetCooldown(st.cdStart, st.cdDur)
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
	if st.count then
		b.count:SetText(st.count)
	else
		b.count:SetText("")
	end
	-- buff on you (the active Aspect, etc.): bright green ring and a soft glow
	if st.active then
		b.ring:SetVertexColor(0.3, 1, 0.45, 1)
		b.glow:Show()
	else
		b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
		b.glow:Hide()
	end
	local r, g, bl, desat = AW.StateTint(st)
	b.icon:SetVertexColor(r, g, bl)
	if b.icon.SetDesaturated then b.icon:SetDesaturated(desat) end
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
					if not AW.IsEmpty(slot) and slot.type ~= "pet" and slot.type ~= "wheel" and slot.type ~= "macro" then
						-- never let a display problem become an error message
						pcall(Paint, page.slices[i], slot)
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
	local minR = math.max(48 + btn / 2 + 8, btn * n / (2 * math.pi) + 4)
	local radius = math.max(S.radius or 105, minR)

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
		b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
		b.cd:SetCooldown(0, 0)
		b.count:SetText("")
		if i <= n then
			local slot = def.items[i]
			if slot and slot.type == "wheel" and not pageOf[slot.wheel] then slot = nil end -- dangling link
			if slot and slot.type == "wheel" then
				b:SetAttribute("subwheel", pageOf[slot.wheel])
				-- the page name is "page<k>": switch with /click ActionWheelsGo<k>
				for key, v in pairs(AW.SecureAttributes(slot, string.match(pageOf[slot.wheel], "%d+"))) do b:SetAttribute(key, v) end
			else
				for key, v in pairs(AW.SecureAttributes(slot)) do b:SetAttribute(key, v) end
			end
			b:SetWidth(btn)
			b:SetHeight(btn)
			b.icon:SetWidth(btn - 14)
			b.icon:SetHeight(btn - 14)
			b.cd:SetWidth(btn - 14)
			b.cd:SetHeight(btn - 14)
			local a = (i - 1) * step -- clockwise from the top
			b:ClearAllPoints()
			b:SetPoint("CENTER", page, "CENTER", math.sin(a) * radius, math.cos(a) * radius)
			local icon = AW.SlotIcon(slot)
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

	-- the wheel being edited opens first, unless an "auto" condition of another wheel holds
	local home = pageOf[p.current] or pageName(1)
	local clauses = {}
	for k, id in ipairs(p.order) do
		local cond = p.wheels[id].auto
		if cond and AW.ValidCondition(cond) then clauses[#clauses + 1] = cond .. " " .. pageName(k) end
	end
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
