-- Playing: moving, the camera, targeting, abilities, interact. Runs last, so the other files' parts are all there.
local N, G = ...

local Protect = G.Protect
local MoveForwardStart, MoveForwardStop = Protect("MoveForwardStart"), Protect("MoveForwardStop")
local MoveBackwardStart, MoveBackwardStop = Protect("MoveBackwardStart"), Protect("MoveBackwardStop")
local StrafeLeftStart, StrafeLeftStop = Protect("StrafeLeftStart"), Protect("StrafeLeftStop")
local StrafeRightStart, StrafeRightStop = Protect("StrafeRightStart"), Protect("StrafeRightStop")
local MouselookStart, MouselookStop = Protect("MouselookStart"), Protect("MouselookStop")
local JumpOrAscendStart, AscendStop = Protect("JumpOrAscendStart"), Protect("AscendStop")
local SitStandOrDescendStart, DescendStop = Protect("SitStandOrDescendStart"), Protect("DescendStop")
local TargetNearestEnemy, TargetNearestFriend = Protect("TargetNearestEnemy"), Protect("TargetNearestFriend")
local ToggleAutoRun = Protect("ToggleAutoRun")
local TargetUnit = Protect("TargetUnit")
local SpellStopTargeting = Protect("SpellStopTargeting")
local ToggleCharacter, ToggleSpellBook = Protect("ToggleCharacter"), Protect("ToggleSpellBook")
local ToggleTalentFrame, OpenAllBags = Protect("ToggleTalentFrame"), Protect("OpenAllBags")
local ToggleFrame, ToggleFriendsFrame = Protect("ToggleFrame"), Protect("ToggleFriendsFrame")
local ToggleLFDParentFrame, ToggleAchievementFrame = Protect("ToggleLFDParentFrame"), Protect("ToggleAchievementFrame")
local ToggleGameMenu = Protect("ToggleGameMenu")

local HOLD_TIME = 0.25       -- a shoulder held this long opens the target ring
local MOVE_ON, MOVE_OFF = 0.42, 0.30
local LOOK_LINGER = 0.6      -- mouselook lets go this long after the sticks do
local INTERACT_RANGE = 6
local SCAN_EVERY = 0.2

-- ---- moving -------------------------------------------------------------------------------------------------

local MOVES = {
	forward = { MoveForwardStart, MoveForwardStop },
	backward = { MoveBackwardStart, MoveBackwardStop },
	left = { StrafeLeftStart, StrafeLeftStop },
	right = { StrafeRightStart, StrafeRightStop },
}
local moving = {}

local function SetMove(which, on)
	if (moving[which] or false) ~= on then
		moving[which] = on or nil
		MOVES[which][on and 1 or 2]()
	end
end

-- With a gap between the on and off points, so a stick resting at the edge can't stutter.
local function Direction(which, value)
	local threshold = moving[which] and MOVE_OFF or MOVE_ON
	return value > threshold
end

local function StopMoving()
	for which in pairs(MOVES) do SetMove(which, false) end
end

local function UpdateMovement()
	SetMove("forward", Direction("forward", G.ly))
	SetMove("backward", Direction("backward", -G.ly))
	SetMove("right", Direction("right", G.lx))
	SetMove("left", Direction("left", -G.lx))
end

-- ---- camera -------------------------------------------------------------------------------------------------

local lookFor = 0
local looking = false
local stickSpeed

local function SetStick(speedX, speedY)
	local key = speedX .. "/" .. speedY
	if stickSpeed ~= key then
		stickSpeed = key
		N.StickMouse(speedX, speedY)
	end
end

local function SetLook(on)
	if looking ~= on then
		looking = on
		if on then MouselookStart() else MouselookStop() end
	end
end

local function UpdateCamera(elapsed)
	if G.RadialOpen() then
		-- The stick is pointing at the ring.
		SetStick(0, 0)
		SetLook(false)
		return
	end
	if G.mode == "cursor" or G.mode == "aim" then
		SetLook(false)
		local speed = G.settings.cursor
		SetStick(speed, speed)
		return
	end
	-- While the character runs, mouselook turns it with the camera, as on a console.
	if G.lx ~= 0 or G.ly ~= 0 or G.rx ~= 0 or G.ry ~= 0 then
		lookFor = LOOK_LINGER
	else
		lookFor = lookFor - elapsed
	end
	if lookFor > 0 then
		SetLook(true)
		local speed = G.settings.camera
		SetStick(speed, G.settings.invert == 1 and -speed or speed)
	else
		SetLook(false)
		SetStick(0, 0)
	end
end

-- ---- targeting ----------------------------------------------------------------------------------------------

-- Everyone worth picking: you, then party or the raid's most hurt.
local function FriendItems()
	local items = {}
	local function add(unit, label)
		if UnitExists(unit) then
			local most = UnitHealthMax(unit)
			items[#items + 1] = {
				label = label or UnitName(unit),
				health = most > 0 and UnitHealth(unit) / most or 0,
				action = function() TargetUnit(unit) end,
			}
		end
	end
	add("player")
	if GetNumRaidMembers() > 0 then
		local hurt = {}
		for i = 1, GetNumRaidMembers() do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				hurt[#hurt + 1] = { unit, UnitHealth(unit) / math.max(UnitHealthMax(unit), 1) }
			end
		end
		table.sort(hurt, function(a, b) return a[2] < b[2] end)
		for i = 1, math.min(#hurt, 8) do add(hurt[i][1]) end
	else
		for i = 1, GetNumPartyMembers() do add("party" .. i) end
		add("pet")
	end
	return items
end

-- Nameplates are the only list of nearby enemies the client's Lua has.
local function NameplateName(frame)
	local regions = { frame:GetRegions() }
	local isPlate, name
	for _, region in ipairs(regions) do
		if region:GetObjectType() == "Texture" and region:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" then
			isPlate = true
		elseif region:GetObjectType() == "FontString" and not name then
			name = region:GetText()
		end
	end
	return isPlate and name or nil
end

local function EnemyItems()
	local items, seen = {}, {}
	local children = { WorldFrame:GetChildren() }
	for _, frame in ipairs(children) do
		if frame:IsVisible() and not frame:GetName() then
			local name = NameplateName(frame)
			if name and not seen[name] then
				seen[name] = true
				if #items < 10 then
					items[#items + 1] = {
						label = name,
						action = function() TargetUnit(name) end,
					}
				end
			end
		end
	end
	return items
end

local TARGETS = {
	RB = { tap = function() TargetNearestEnemy() end, items = EnemyItems, title = "Enemies",
		fallback = function() TargetNearestEnemy(true) end },
	LB = { tap = function() TargetNearestFriend() end, items = FriendItems, title = "Friends",
		fallback = function() TargetNearestFriend(true) end },
}

local shoulder, shoulderHeld, shoulderUsed

local function ShoulderDown(name)
	shoulder, shoulderHeld, shoulderUsed = name, 0, false
end

local function ShoulderUp(name)
	if shoulder == name then
		if not shoulderUsed then TARGETS[name].tap() end
		shoulder = nil
	end
end

local function UpdateShoulder(elapsed)
	if not shoulder or shoulderUsed then return end
	shoulderHeld = shoulderHeld + elapsed
	if shoulderHeld >= HOLD_TIME then
		shoulderUsed = true
		local target = TARGETS[shoulder]
		if not G.OpenRadial(target.title, target.items(), shoulder) then
			-- Nothing to list (plates turned off): step backward through targets instead.
			target.fallback()
		end
	end
end

-- ---- the game's windows, by ring ----------------------------------------------------------------------------

local function Open(func, ...)
	local args = { ... }
	return function()
		func(unpack(args))
	end
end

local function MenuItems()
	local items = {
		{ label = CHARACTER_BUTTON, icon = "Interface\\Icons\\INV_Chest_Cloth_17", action = Open(ToggleCharacter, "PaperDollFrame") },
		{ label = SPELLBOOK_ABILITIES_BUTTON, icon = "Interface\\Icons\\INV_Misc_Book_09", action = Open(ToggleSpellBook, BOOKTYPE_SPELL) },
		{ label = TALENTS_BUTTON, icon = "Interface\\Icons\\Ability_Marksmanship", action = Open(ToggleTalentFrame) },
		{ label = BAGSLOT or "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_08", action = Open(OpenAllBags) },
		{ label = WORLD_MAP, icon = "Interface\\Icons\\INV_Misc_Map_01", action = Open(ToggleFrame, WorldMapFrame) },
		{ label = QUESTLOG_BUTTON, icon = "Interface\\Icons\\INV_Misc_Note_01", action = Open(ToggleFrame, QuestLogFrame) },
		{ label = SOCIAL_BUTTON, icon = "Interface\\Icons\\INV_Letter_15", action = Open(ToggleFriendsFrame) },
		{ label = LFG_TITLE or "Dungeon Finder", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", action = Open(ToggleLFDParentFrame) },
		{ label = ACHIEVEMENT_BUTTON, icon = "Interface\\Icons\\Achievement_General", action = Open(ToggleAchievementFrame) },
		{ label = MAINMENU_BUTTON, icon = "Interface\\Icons\\INV_Misc_Gear_01", action = Open(ToggleGameMenu) },
	}
	return items
end

-- ---- interact -----------------------------------------------------------------------------------------------

local scanIn = 0
local nearbyKind, nearbyHigh, nearbyLow

local function UpdateScan(elapsed)
	scanIn = scanIn - elapsed
	if scanIn > 0 then return end
	scanIn = SCAN_EVERY
	if G.mode ~= "world" or InCombatLockdown() or UnitIsDeadOrGhost("player") then
		nearbyKind = nil
	else
		nearbyKind, nearbyHigh, nearbyLow = N.ScanInteract(INTERACT_RANGE)
	end
	G.ShowPrompt(nearbyKind)
end

local function SouthDown()
	if nearbyKind and not InCombatLockdown() then
		N.Call(N.Interact, nearbyHigh, nearbyLow)
		if G.settings.rumble == 1 then N.Rumble(0.1, 0.2, 60) end
		return
	end
	JumpOrAscendStart()
end

-- ---- buttons ------------------------------------------------------------------------------------------------

local aimClick = false

G.handlers.aim = function(name, down)
	if name == "SOUTH" and (down or aimClick) then
		aimClick = down
		N.MouseButton("left", down)
		if not down and not SpellIsTargeting() then G.SetMode("world") end
		return true
	end
	if name == "EAST" then
		if down then
			SpellStopTargeting()
			G.SetMode("world")
		end
		return true
	end
	return false
end

G.handlers.world = function(name, down)
	if down and not N.InWorld() then return end
	-- Let go of a jump even if the mode changed while it was held.
	if name == "SOUTH" and not down then
		AscendStop()
		return
	end
	if name == "R3" and not down then
		DescendStop()
		return
	end
	if TARGETS[name] then
		if down then ShoulderDown(name) else ShoulderUp(name) end
		return
	end
	if not down then return end

	if name == "START" then
		G.OpenRadial(MAINMENU_BUTTON, MenuItems())
	elseif name == "BACK" then
		G.EnterCursor(true)
	elseif name == "L3" then
		ToggleAutoRun()
	elseif name == "R3" then
		SitStandOrDescendStart()
	elseif name == "LT" or name == "RT" or name == "GUIDE" then
		-- Layer keys: held state is all that matters.
		return
	elseif name == "SOUTH" and G.Layer() == "BASE" then
		SouthDown()
	else
		local slot = G.ActionFor(name)
		if slot then G.UseSlot(slot) end
	end
end

-- ---- every frame --------------------------------------------------------------------------------------------

local letGo

-- The events only leave a note. Their handler is a frame script any addon can find and call, and only the frame
-- function can run protected calls clean.
local stopPending = false
local ForceStop

G.Listen("update", function(elapsed, inFront)
	if stopPending then
		stopPending = false
		ForceStop()
	end
	if not inFront then
		letGo()
		return
	end
	-- Keys aren't read through a loading screen either.
	if not N.InWorld() then return end
	UpdateMovement()
	UpdateCamera(elapsed)
	UpdateShoulder(elapsed)
	UpdateScan(elapsed)
	if G.mode == "aim" and not SpellIsTargeting() then
		G.SetMode("world")
	end
end)

letGo = function()
	StopMoving()
	lookFor = 0
	SetLook(false)
	SetStick(0, 0)
	shoulder = nil
	nearbyKind = nil
	G.ShowPrompt(nil)
end

G.Listen("release", letGo)
G.Listen("active", function(active)
	if not active then letGo() end
end)

G.Listen("mode", function(mode)
	if mode ~= "world" then
		lookFor = 0
		G.ShowPrompt(nil)
	end
	-- A spell can resolve on the press, ending aim mode with the button still down.
	if mode ~= "aim" and aimClick then
		aimClick = false
		N.MouseButton("left", false)
	end
end)

-- Stop for certain rather than assume the client already has. Only with a controller around: a stop at each loading
-- screen would interrupt a keyboard player too.
ForceStop = function()
	moving = {}
	looking = false
	stickSpeed = nil
	lookFor = 0
	N.StickMouse(0, 0)
	MoveForwardStop()
	MoveBackwardStop()
	StrafeLeftStop()
	StrafeRightStop()
	MouselookStop()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent", function()
	stopPending = true
end)

-- Loaded by a /reload with a controller plugged in: whatever the old UI had going may still be going.
if N.Poll() then ForceStop() end

N.Log("world loaded")
