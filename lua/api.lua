-- C_Controller: what an addon may know about the controller, so it can show the abilities on its own action bars.
-- Read only. Every function returns plain values, never one of the controller's tables, and the two requests an addon
-- can make go through the same text queue as /controller, so they reach the controller's code as clean text. The
-- controller never calls an addon's code. Created after addons have loaded, so look it up when it's needed.
local N, G = ...

-- bar, then slot on that bar: the button and trigger layer that use it.
local BINDINGS = { main = {}, bottomleft = {}, bottomright = {} }
for layer, refs in pairs(G.actionMap) do
	for position, ref in pairs(refs) do
		BINDINGS[ref[1]][ref[2]] = { position, layer }
	end
end

local api = {}

-- Whether a controller is plugged in and turned on (/controller off counts as not); whether it's in use now (a button pressed since it was plugged in or last rested);
-- its button art family: "ltr" Xbox, "shp" PlayStation, "rev" Nintendo, "gen" other; the trigger layer held: "BASE",
-- "LT", "RT" or "BOTH"; and what the sticks are doing: "world", "cursor" (working a window) or "aim" (placing a spell).
function api.GetState()
	local on = G.settings.enabled == 1
	return G.connected and on, G.active and on, G.family, G.Layer(), G.mode
end

-- The button ("SOUTH", "EAST", "WEST", "NORTH", "UP", "RIGHT", "DOWN", "LEFT") and layer that use a slot of the main
-- bar, "bottomleft" or "bottomright" bar, 1 to 12. Nothing for a slot no button uses.
function api.GetBinding(bar, index)
	local entry = BINDINGS[bar] and BINDINGS[bar][index]
	if entry then return entry[1], entry[2] end
end

-- The picture of a button, for the controller in use: texture path, then left, right, top and bottom texture
-- coordinates. Buttons are the eight above plus "LT", "RT", "LB", "RB", "START", "BACK", "L3" and "R3".
function api.GetGlyph(button)
	local set = G.Atlas[G.family] or G.Atlas.ltr
	local cell = set[button]
	if cell then
		return "Interface\\GamePad\\" .. cell[1], cell[2], cell[3], cell[4], cell[5]
	end
end

-- Back to keyboard and mouse: the controller lets go of everything and goes quiet until its next button press.
function api.Rest()
	N.PostCommand("rest")
end

-- True while the addon shows the abilities on its own bars: the controller's own cross of abilities stays hidden.
-- Lasts until a reload of the interface.
function api.SetBarsShown(shown)
	N.PostCommand(shown and "ownbars 1" or "ownbars 0")
end

C_Controller = api
N.Log("addon API ready")
