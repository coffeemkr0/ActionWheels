-- Tracker: a small on-screen strip of cooldown icons, visible with the wheel closed, so you can
-- see when a long cooldown is ready again. It is NOT clickable (plain frames), so it is not subject
-- to the combat restrictions on the wheel itself.
--   * a spell slot with "On cooldown strip" ticked is always shown (dim while cooling down)
--   * with "automatic" on, any spell on a wheel whose cooldown is at least `threshold` seconds is
--     shown while it cools down, and for a few seconds after it is ready
--   * a flash (and optionally a sound) when a tracked spell comes off cooldown
ActionWheels = ActionWheels or {}
local AW = ActionWheels

local WHITE = "Interface\\Buttons\\WHITE8X8"
local READY_SHOW = 6 -- seconds an automatically tracked icon stays visible after it is ready
local frame
local icons = {}
AW.trackerList = {}

local function T() return ActionWheelsDB and ActionWheelsDB.tracker end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end

-- The spell a slot stands for (a macro with #showtooltip counts as the spell it points at).
local function slotSpell(slot)
	if AW.IsEmpty(slot) then return nil end
	if slot.type == "spell" then return slot.spell end
	if slot.type == "macro" then
		local v = AW.MacroTooltipSlot(slot.macrotext)
		if v and v.type == "spell" then return v.spell end
	end
end
AW.TrackerSlotSpell = slotSpell

-- How long the spell's cooldown is, in seconds (0 when unknown). Uses the game's base cooldown,
-- else what we saw it do out of combat.
local function baseCooldown(name)
	local id = AW.SpellIdOf and AW.SpellIdOf(name)
	if id and GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, id)
		if ok and type(ms) == "number" and not secret(ms) and ms > 0 then return ms / 1000 end
	end
	local cfg = T()
	return (cfg and cfg.learned and cfg.learned[name]) or 0
end
AW.TrackerBaseCooldown = baseCooldown

-- The spells to show, in wheel order: { { name, manual }, ... }
function AW.TrackerCollect()
	local cfg, p = T(), AW.P()
	local out, seen = {}, {}
	if not cfg then return out end
	for _, id in ipairs(p.order) do
		local w = p.wheels[id]
		for i = 1, w.slots do
			local slot = w.items[i]
			local name = slotSpell(slot)
			if name then
				local manual = slot.track and true or false
				if seen[name] then
					if manual then seen[name].manual = true end
				else
					local auto = cfg.auto and baseCooldown(name) >= cfg.threshold
					if manual or auto then
						local e = { name = name, manual = manual }
						seen[name] = e
						out[#out + 1] = e
					end
				end
			end
		end
	end
	return out
end

-- Is this entry on screen right now? Manual ones always are; automatic ones while cooling down and
-- for READY_SHOW seconds afterwards.
function AW.TrackerVisible(entry, running, now)
	if entry.manual then return true end
	if running then entry.lastRunning = now return true end
	return entry.lastRunning ~= nil and (now - entry.lastRunning) < READY_SHOW
end

-- Tracks running -> not running. Returns true exactly once when the cooldown has just finished.
function AW.TrackerTransition(entry, running)
	local was = entry.wasRunning
	entry.wasRunning = running
	return was == true and running == false
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function BuildIcon(i)
	local ic = CreateFrame("Frame", "ActionWheelsTrackerIcon" .. i, frame)
	ic:SetWidth(36)
	ic:SetHeight(36)
	ic.bg = ic:CreateTexture(nil, "BACKGROUND")
	ic.bg:SetAllPoints(ic)
	ic.bg:SetTexture(WHITE)
	ic.bg:SetVertexColor(0.05, 0.05, 0.09, 0.9)
	ic.tex = ic:CreateTexture(nil, "ARTWORK")
	ic.tex:SetPoint("CENTER", ic, "CENTER", 0, 0)
	ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
	ic.cd:SetPoint("CENTER", ic, "CENTER", 0, 0)
	ic.cd:EnableMouse(false)
	if ic.cd.SetHideCountdownNumbers then ic.cd:SetHideCountdownNumbers(false) end -- the countdown text
	ic.border = AW.SquareBorder(ic, "BORDER", 2)
	ic.flash = ic:CreateTexture(nil, "OVERLAY")
	ic.flash:SetAllPoints(ic)
	ic.flash:SetTexture(WHITE)
	ic.flash:SetBlendMode("ADD")
	ic.flash:Hide()
	ic:Hide()
	ic.cdStart, ic.cdDur, ic.flashT, ic.texNow = false, false, false, false
	ic.cd:SetScript("OnCooldownDone", function()
		if ic.entry and AW.TrackerTransition(ic.entry, false) then AW.TrackerReady(ic) end
	end)
	icons[i] = ic
	return ic
end

function AW.TrackerReady(ic)
	local cfg = T()
	if not cfg then return end
	if cfg.flash then
		ic.flashT = GetTime()
		ic.flash:SetVertexColor(1, 0.9, 0.3)
		ic.flash:SetAlpha(0.8)
		ic.flash:Show()
	end
	if cfg.sound and PlaySound then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or "ReadyCheck")
	end
end

local function Place()
	local cfg = T()
	if not (frame and cfg) then return end
	frame:ClearAllPoints()
	if cfg.x and cfg.y then frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.x, cfg.y)
	else frame:SetPoint("CENTER", UIParent, "CENTER", 0, -260) end
end

local ANCHORS = { right = "TOPLEFT", down = "TOPLEFT", left = "TOPRIGHT", up = "BOTTOMLEFT" }

-- Called every 0.2s (and on demand): refresh cooldowns, decide who is visible, lay the row out.
function AW.TrackerUpdate()
	local cfg = T()
	if not (frame and cfg and ActionWheelsDB.profile) then return end
	if cfg.hide then frame:Hide() return end
	local now = GetTime()
	local size = cfg.size or 36
	local gap = 4
	local step = size + gap
	local shown = 0
	local dir = cfg.dir or "right"
	frame:SetWidth(size)
	frame:SetHeight(size)
	for i, e in ipairs(AW.trackerList) do
		local ic = icons[i] or BuildIcon(i)
		ic.entry = e
		local spec = { type = "spell", spell = e.name }
		local st = AW.SlotState(spec)
		local running
		if st.cdSecret then
			if st.cdObject and ic.cd.SetCooldownFromDurationObject then
				ic.cd:SetCooldownFromDurationObject(st.cdObject, true)
			else
				pcall(ic.cd.SetCooldown, ic.cd, st.cdStart, st.cdDur)
			end
			ic.cdStart = false
			running = ic.cd:IsShown() and true or false
		elseif st.cdStart and st.cdDur and st.cdDur > 0 then
			if ic.cdStart ~= st.cdStart or ic.cdDur ~= st.cdDur then
				ic.cd:SetCooldown(st.cdStart, st.cdDur)
				ic.cdStart, ic.cdDur = st.cdStart, st.cdDur
			end
			running = true
			-- remember how long this spell's cooldown really is (for spells the game won't report)
			if cfg.learned and st.cdDur >= 10 and (cfg.learned[e.name] or 0) < st.cdDur then
				cfg.learned[e.name] = st.cdDur
			end
		else
			if ic.cdStart then ic.cd:SetCooldown(0, 0); ic.cdStart = false end
			running = false
		end
		if AW.TrackerTransition(e, running) then AW.TrackerReady(ic) end
		if AW.TrackerVisible(e, running, now) then
			shown = shown + 1
			ic:SetWidth(size)
			ic:SetHeight(size)
			ic.tex:SetWidth(size - 4)
			ic.tex:SetHeight(size - 4)
			ic.cd:SetWidth(size - 4)
			ic.cd:SetHeight(size - 4)
			local tex = AW.SlotIcon(spec)
			if tex ~= nil and not secret(tex) and ic.texNow ~= tex then ic.tex:SetTexture(tex); ic.texNow = tex end
			if ic.tex.SetDesaturated then ic.tex:SetDesaturated(running) end
			ic.tex:SetVertexColor(1, 1, 1)
			if running then ic.border:SetVertexColor(0.4, 0.45, 0.55, 1) else ic.border:SetVertexColor(0.3, 1, 0.45, 1) end -- ready: green
			local off = (shown - 1) * step
			ic:ClearAllPoints()
			if dir == "right" then ic:SetPoint("TOPLEFT", frame, "TOPLEFT", off, 0)
			elseif dir == "down" then ic:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -off)
			elseif dir == "left" then ic:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -off, 0)
			else ic:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, off) end
			ic:Show()
		else
			ic:Hide()
		end
		-- the ready flash fades out
		if ic.flashT then
			local a = 1 - (now - ic.flashT) / 1.2
			if a <= 0 then ic.flash:Hide(); ic.flashT = false else ic.flash:SetAlpha(a * 0.8) end
		end
	end
	for i = #AW.trackerList + 1, #icons do icons[i]:Hide() end
	if cfg.locked then frame.mover:Hide() else frame.mover:Show() end
	frame:EnableMouse(not cfg.locked)
	frame:Show()
end

-- Rebuild the list of tracked spells (after slots, wheels or tracker settings change).
function AW.TrackerRefresh()
	if not frame then return end
	local old = {}
	for _, e in ipairs(AW.trackerList) do old[e.name] = e end
	AW.trackerList = AW.TrackerCollect()
	for _, e in ipairs(AW.trackerList) do -- keep the running / ready memory of spells that stay on the list
		local o = old[e.name]
		if o then e.wasRunning, e.lastRunning = o.wasRunning, o.lastRunning end
	end
	Place()
	AW.TrackerUpdate()
end

function AW.BuildTracker()
	if frame then return end
	frame = CreateFrame("Frame", "ActionWheelsTracker", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetWidth(36)
	frame:SetHeight(36)
	-- the box you drag while the strip is unlocked (shown even when nothing is on cooldown)
	frame.mover = CreateFrame("Frame", nil, frame)
	frame.mover:SetAllPoints(frame)
	frame.mover.bg = frame.mover:CreateTexture(nil, "BACKGROUND")
	frame.mover.bg:SetAllPoints(frame.mover)
	frame.mover.bg:SetTexture(WHITE)
	frame.mover.bg:SetVertexColor(0.2, 0.55, 1, 0.35)
	frame.mover.text = frame.mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.mover.text:SetPoint("CENTER", frame.mover, "CENTER", 0, 0)
	frame.mover.text:SetText("drag")
	frame.mover:Hide()
	frame:SetScript("OnDragStart", function(self)
		local cfg = T()
		if cfg and not cfg.locked then self.moving = true; self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = false
		self:StopMovingOrSizing()
		local cfg = T()
		cfg.x, cfg.y = self:GetLeft(), self:GetTop()
		Place()
	end)
	local acc = 0
	frame:SetScript("OnUpdate", function(_, dt)
		acc = acc + (dt or 0)
		if acc >= 0.2 then acc = 0; AW.TrackerUpdate() end
	end)
	AW.trackerList = AW.TrackerCollect()
	Place()
	AW.TrackerUpdate()
end

function AW.TrackerResetPosition()
	local cfg = T()
	if not cfg then return end
	cfg.x, cfg.y = nil, nil
	Place()
end
