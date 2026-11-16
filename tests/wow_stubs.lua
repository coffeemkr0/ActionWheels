-- Minimal WoW API stubs so the addon files can be loaded and exercised outside the game.
local printed = {}
_PRINTED = printed
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
SlashCmdList = {}
UISpecialFrames = {}
tinsert = table.insert
_COMBAT = false
function InCombatLockdown() return _COMBAT end
function UnitAffectingCombat() return _COMBAT end

local proxy
local mt = {}
mt.__index = function(t, k)
	if k == "SetAttribute" then return function(self, a, v) local t = rawget(self, "_attr") or {}; rawset(self, "_attr", t); t[a] = v end end
	if k == "GetAttribute" then return function(self, a) return (rawget(self, "_attr") or {})[a] end end
	if k == "SetScript" then return function(self, name, fn) rawset(self, "_" .. name, fn) end end
	if k == "IsShown" then return function(self) return rawget(self, "_shown") or false end end
	if k == "Show" then return function(self) rawset(self, "_shown", true) end end
	if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
	if k == "GetFrameLevel" then return function() return 10 end end
	if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
	if k == "GetCenter" then return function() return 100, 100 end end
	if k == "GetEffectiveScale" then return function() return 1 end end
	if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
	if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
	if k == "SetChecked" then return function(self, v) rawset(self, "_checked", v) end end
	if k == "GetChecked" then return function(self) return rawget(self, "_checked") end end
	if k == "SetTexture" then return function(self, tx) rawset(self, "_tex", tx) end end
	if k == "SetScale" then return function(self, s) rawset(self, "_scale", s) end end
	return function(self) return proxy() end
end
proxy = function() return setmetatable({}, mt) end
function CreateFrame(_, name) local f = proxy(); if name then _G[name] = f end; return f end
UIParent = proxy()
_WRAPS = {}
function SecureHandlerWrapScript(frame, script, header, pre, post) _WRAPS[#_WRAPS + 1] = { frame, script, pre, post } end
function GetSpellTexture(name) return "Interface\\Icons\\Spell_" .. name end

_STATEDRV = {}
function RegisterStateDriver(f, state, v) _STATEDRV[state] = v end
function UnregisterStateDriver(f, state) _STATEDRV[state] = nil end
Minimap = proxy()
GameTooltip = proxy()
function GetCursorPosition() return 500, 400 end
function GetTime() return 1000 end
_CLEARED = 0
function ClearCursor() _CLEARED = _CLEARED + 1 end
