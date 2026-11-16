-- Wheel: the radial menu, built from secure frames so it opens and acts in combat.
--
-- How combat works:
--   * ActionWheelsToggle is a secure click handler bound to your key. Its snippet runs in the
--     restricted environment, so it may show/hide and position the protected wheel in combat.
--   * Every slice is a SecureActionButton (spell / item / macro attributes) wrapped so the
--     wheel closes after the click.
--   * Attributes, positions and icons can only change out of combat. ApplyLayout() does that
--     and, if called in combat, waits for PLAYER_REGEN_ENABLED.
ActionWheels = ActionWheels or {}
local AW = ActionWheels

local TEX = "Interface\\AddOns\\ActionWheels\\Textures\\"
local root, toggle, catcher
local slices = {}

local function Build()
	root = CreateFrame("Frame", "ActionWheelsRoot", UIParent, "SecureHandlerBaseTemplate")
	root:SetFrameStrata("DIALOG")
	root:SetWidth(96)
	root:SetHeight(96)
	root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	root:Hide()

	-- click anywhere outside the wheel to close it
	catcher = CreateFrame("Button", "ActionWheelsCatcher", root, "SecureHandlerClickTemplate")
	catcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	catcher:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	catcher:SetFrameLevel(root:GetFrameLevel())
	catcher:RegisterForClicks("AnyUp")
	catcher:SetAttribute("_onclick", [[ self:GetParent():Hide() ]])

	root.hubBg = root:CreateTexture(nil, "BACKGROUND")
	root.hubBg:SetTexture(TEX .. "Circle")
	root.hubBg:SetVertexColor(0.04, 0.04, 0.08, 0.9)
	root.hubBg:SetPoint("CENTER", root, "CENTER", 0, 0)
	root.hubBg:SetWidth(96)
	root.hubBg:SetHeight(96)
	root.name = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	root.name:SetPoint("CENTER", root, "CENTER", 0, 0)
	root.name:SetWidth(84)

	for i = 1, AW.MAXSLOTS do
		local b = CreateFrame("Button", "ActionWheelsSlice" .. i, root, "SecureActionButtonTemplate")
		b:SetFrameLevel(root:GetFrameLevel() + 2)
		b:RegisterForClicks("LeftButtonUp") -- right-click is reserved for editing (not a secure action)
		b.index = i
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints(b)
		b.bg:SetTexture(TEX .. "Circle")
		b.bg:SetVertexColor(0.07, 0.07, 0.11, 0.92)
		b.ring = b:CreateTexture(nil, "BORDER")
		b.ring:SetAllPoints(b)
		b.ring:SetTexture(TEX .. "Ring")
		b.ring:SetVertexColor(0.4, 0.45, 0.55, 1)
		b.hl = b:CreateTexture(nil, "ARTWORK")
		b.hl:SetAllPoints(b)
		b.hl:SetTexture(TEX .. "Circle")
		b.hl:SetVertexColor(0.2, 0.55, 1, 0.6)
		b.hl:Hide()
		b.icon = b:CreateTexture(nil, "OVERLAY")
		b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.icon:Hide()
		b:HookScript("OnEnter", function(self)
			self.hl:Show()
			local def = AW.P().wheels[AW.P().current]
			root.name:SetText(AW.DescribeSlot(def and def.items[self.index]))
		end)
		b:HookScript("OnLeave", function(self)
			self.hl:Hide()
			root.name:SetText("")
		end)
		-- close the wheel after the click has run (post-handler runs in the secure environment)
		SecureHandlerWrapScript(b, "OnClick", root, "", [[ owner:Hide() ]])
		slices[i] = b
	end

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
end

function AW.BuildWheel()
	if root then return end
	Build()
end

-- Push the current profile onto the secure frames. Out of combat only; otherwise deferred.
function AW.ApplyLayout()
	if not root then return false end
	if AW.InCombat() then
		AW.pendingApply = true
		return false
	end
	AW.pendingApply = false
	local p = AW.P()
	local S = p.settings
	local def = p.wheels[p.current]
	local n = def.slots
	local btn = S.buttonSize or 56
	local minR = math.max(48 + btn / 2 + 8, btn * n / (2 * math.pi) + 4)
	local radius = math.max(S.radius or 105, minR)

	root:SetScale(S.scale or 1)
	toggle:SetAttribute("mode", S.openMode or "toggle")
	toggle:SetAttribute("at", S.openAt or "cursor")

	local step = 2 * math.pi / n
	for i = 1, AW.MAXSLOTS do
		local b = slices[i]
		for _, key in ipairs(AW.ATTR_KEYS) do b:SetAttribute(key, nil) end
		if i <= n then
			local slot = def.items[i]
			for k, v in pairs(AW.SlotAttributes(slot)) do b:SetAttribute(k, v) end
			b:SetWidth(btn)
			b:SetHeight(btn)
			b.icon:SetWidth(btn - 14)
			b.icon:SetHeight(btn - 14)
			local a = (i - 1) * step -- clockwise from the top
			b:ClearAllPoints()
			b:SetPoint("CENTER", root, "CENTER", math.sin(a) * radius, math.cos(a) * radius)
			local icon = AW.SlotIcon(slot)
			if icon then
				b.icon:SetTexture(icon)
				b.icon:Show()
			else
				b.icon:Hide()
			end
			b:Show()
		else
			b:Hide()
		end
	end
	return true
end
