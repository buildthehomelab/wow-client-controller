-- Which button uses which action bar slot. Base buttons are the first abilities, then the triggers as modifiers,
-- the way Forever does it. South on the base layer stays free for jump and interact.
local N, G = ...

-- Fill order inside a layer.
local POSITIONS = { "SOUTH", "EAST", "WEST", "NORTH", "UP", "RIGHT", "DOWN", "LEFT" }
G.POSITIONS = POSITIONS

local LAYERS = { "BASE", "LT", "RT", "BOTH" }

local TargetNearestEnemy = G.Protect("TargetNearestEnemy")
local UseAction = G.Protect("UseAction")

-- bar, position on that bar: 12 main, 12 bottom left, then bottom right as far as buttons last.
local function BuildMap()
	local sequence = {}
	for i = 1, 12 do sequence[#sequence + 1] = { "main", i } end
	for i = 1, 12 do sequence[#sequence + 1] = { "bottomleft", i } end
	for i = 1, 12 do sequence[#sequence + 1] = { "bottomright", i } end
	local map, next_index = {}, 1
	for _, layer in ipairs(LAYERS) do
		map[layer] = {}
		for _, position in ipairs(POSITIONS) do
			if not (layer == "BASE" and position == "SOUTH") then
				map[layer][position] = sequence[next_index]
				next_index = next_index + 1
			end
		end
	end
	return map
end

G.actionMap = BuildMap()

local BAR_FIRST_SLOT = { bottomleft = 61, bottomright = 49 }

-- The real slot right now, following stance, stealth, page and vehicle the way the bar itself does.
function G.SlotOf(ref)
	local bar, index = ref[1], ref[2]
	if bar ~= "main" then
		return BAR_FIRST_SLOT[bar] + index - 1
	end
	if VehicleMenuBar and VehicleMenuBar:IsShown() and index <= VEHICLE_MAX_ACTIONBUTTONS then
		local button = _G["VehicleMenuBarActionButton" .. index]
		if button and button.action then return button.action end
	end
	local page = GetActionBarPage()
	if page == 1 then
		local offset = GetBonusBarOffset()
		if offset > 0 then page = NUM_ACTIONBAR_PAGES + offset end
	end
	return index + (page - 1) * NUM_ACTIONBAR_BUTTONS
end

function G.ActionFor(position, layer)
	local refs = G.actionMap[layer or G.Layer()]
	local ref = refs and refs[position]
	return ref and G.SlotOf(ref) or nil
end

local function NeedsEnemy(slot)
	local kind, id = GetActionInfo(slot)
	if kind ~= "spell" or not id then return false end
	if not IsHarmfulSpell(id, BOOKTYPE_SPELL) then return false end
	return not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target")
end

function G.UseSlot(slot)
	if not HasAction(slot) then return end
	if G.settings.autotarget == 1 and NeedsEnemy(slot) then
		TargetNearestEnemy()
	end
	UseAction(slot)
	-- Blizzard, Flamestrike and such: aim with the stick, press to place.
	if SpellIsTargeting() then
		G.SetMode("aim")
	end
end
