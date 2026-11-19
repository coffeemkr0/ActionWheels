-- Default settings and the starter wheel.
ActionWheels = ActionWheels or {}
local AW = ActionWheels

AW.DEFAULT_SETTINGS = {
	openMode = "toggle",  -- "toggle" (press to open, press again to close) or "hold" (open while the key is held)
	openAt = "cursor",    -- "cursor" or "center"
	scale = 1,
	radius = 105,         -- minimum ring radius (grows if the buttons need room)
	buttonSize = 56,
	openFirst = "selected", -- which wheel the key opens: "selected" (the one being edited) or "last" (last used)
	wheelScroll = true,     -- the mouse wheel switches wheels while the wheel is open
	wheelReverse = false,   -- reverse the scroll direction
	closeMode = "success", -- after a click: "success" (spells stay open until they cast), "click", "never"
}

function AW.DefaultWheels()
	local wheels = {
		main = {
			name = "Main", slots = 8,
			items = {
				{ type = "pet", pet = "attack" },
				{ type = "pet", pet = "follow" },
				{ type = "pet", pet = "stay" },
				{ type = "pet", pet = "passive" },
				{ type = "pet", pet = "defensive" },
				{ type = "pet", pet = "assist" },
				{ type = "item", item = "Hearthstone" },
				{ type = "macro", macrotext = "/dismount", label = "Dismount", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
			},
		},
	}
	return wheels, { "main" }
end
