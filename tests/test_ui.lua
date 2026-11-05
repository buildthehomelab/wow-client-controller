-- luajit tests/test_ui.lua (from the repo root). A pretend client and pretend controller drive the real UI files.
local calls = {}
local function record(name, ...)
	calls[#calls + 1] = { name, ... }
end
local function called(name, a)
	for _, c in ipairs(calls) do
		if c[1] == name and (a == nil or c[2] == a) then return true end
	end
	return false
end
local function count(name)
	local n = 0
	for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
	return n
end
local function clear() calls = {} end

local failures, checks = 0, 0
local function check(ok, what)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		print("FAIL " .. what)
	end
end

-- ---- pretend frames ------------------------------------------------------------------------------------------
local onUpdates, frames = {}, {}
local FrameMeta = {}
FrameMeta.__index = function(self, key)
	local method = rawget(FrameMeta, key)
	if method then return method end
	if key == "action" then return nil end -- a data field real frames only sometimes have
	return function() end
end
function FrameMeta.SetScript(self, name, func)
	self.scripts[name] = func
	if name == "OnUpdate" then onUpdates[#onUpdates + 1] = func end
end
function FrameMeta.GetScript(self, name) return self.scripts[name] end
function FrameMeta.HasScript() return true end
function FrameMeta.Show(self) self.shown = true end
function FrameMeta.Hide(self) self.shown = false end
function FrameMeta.IsShown(self) return self.shown end
function FrameMeta.IsVisible(self) return self.shown end
function FrameMeta.IsMouseEnabled() return true end
function FrameMeta.GetFrameLevel() return 1 end
function FrameMeta.GetEffectiveScale() return 1 end
function FrameMeta.GetWidth() return 40 end
function FrameMeta.GetHeight() return 40 end
function FrameMeta.GetCenter(self) return self.cx, self.cy end
function FrameMeta.GetFrameStrata() return "DIALOG" end
function FrameMeta.CreateTexture(self) return setmetatable({ scripts = {}, shown = true }, FrameMeta) end
function FrameMeta.CreateFontString(self) return setmetatable({ scripts = {}, shown = true }, FrameMeta) end
function FrameMeta.RegisterEvent(self, event)
	if not rawget(self, "events") then rawset(self, "events", {}) end
	self.events[event] = true
end
function FrameMeta.GetButtonState(self) return rawget(self, "state") or "NORMAL" end
function FrameMeta.SetButtonState(self, state) self.state = state end
function FrameMeta.GetChildren() return end
function FrameMeta.SetSize(self, w, h) self.w, self.h = w, h end
function FrameMeta.SetAlpha(self, a) self.alpha = a end
function FrameMeta.SetPoint(self, ...) self.point = { ... } end
function FrameMeta.GetRegions() return end
local function newFrame()
	local f = setmetatable({ scripts = {}, shown = true }, FrameMeta)
	frames[#frames + 1] = f
	return f
end

_G.CreateFrame = function(kind, name, parent, template)
	local f = newFrame()
	rawset(f, "frameName", name)
	rawset(f, "template", template)
	return f
end
function FrameMeta.GetName(self) return rawget(self, "frameName") end
function FrameMeta.SetChecked(self, on) rawset(self, "checked", on and true or false) end
function FrameMeta.GetChecked(self) return rawget(self, "checked") end
_G.UIParent = newFrame()
_G.WorldFrame = newFrame()
_G.GetScreenWidth = function() return 1000 end
_G.GetScreenHeight = function() return 500 end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) record("say", m) end }
_G.SlashCmdList = {}
_G.issecure = function() return true end

-- ---- pretend game state --------------------------------------------------------------------------------------
local game = { page = 1, offset = 0, targeting = false, combat = false, windows = {}, target = nil, actions = {},
	enumerate = {} }
_G.GetActionBarPage = function() return game.page end
_G.GetBonusBarOffset = function() return game.offset end
_G.NUM_ACTIONBAR_PAGES, _G.NUM_ACTIONBAR_BUTTONS, _G.VEHICLE_MAX_ACTIONBUTTONS = 6, 12, 6
_G.BOOKTYPE_SPELL = "spell"
_G.HasAction = function() return true end
_G.UseAction = function(slot, unit)
	record("UseAction", slot, unit)
	if game.castTargets then game.targeting = true end
	-- For holding: the global cooldown the use starts.
	if game.gcd then game.cooldown[slot] = game.now + game.gcd end
end
_G.SpellIsTargeting = function() return game.targeting end
_G.SpellStopTargeting = function() record("SpellStopTargeting") game.targeting = false end
_G.GetActionInfo = function(slot)
	if game.actions[slot] == "mount" then return "companion", 1, "MOUNT" end
	return game.actions[slot] and "spell", game.actions[slot]
end
_G.IsHarmfulSpell = function(id) return id == "fireball" end
_G.UnitExists = function(u) return u == "player" or (u == "target" and game.target) or (u == "party1" and game.party) end
_G.UnitCanAttack = function() return game.target == "enemy" end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitName = function(u) return u end
_G.UnitHealth = function() return 50 end
_G.UnitHealthMax = function() return 100 end
_G.UnitIsUnit = function() return false end
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return game.party and 1 or 0 end
_G.InCombatLockdown = function() return game.combat end
_G.GetCursorPosition = function() return 500, 250 end
_G.EnumerateFrames = function(previous)
	local list = game.enumerate
	if not previous then return list[1] end
	for i, f in ipairs(list) do if f == previous then return list[i + 1] end end
end
_G.GetUIPanel = function(side) return game.windows[side] end
_G.CursorHasItem = function() return false end
_G.CursorHasSpell = function() return false end
_G.GetActionTexture = function() return "icon" end
_G.IsUsableAction = function() return true end
_G.IsActionInRange = function() return 1 end
_G.GetActionCooldown = function(slot)
	local ready = game.cooldown and game.cooldown[slot]
	if ready and ready > game.now then return ready - 1.5, 1.5, 1 end
	return 0, 0, 1
end
_G.GetActionCount = function() return 0 end
_G.IsConsumableAction = function() return false end
_G.IsStackableAction = function() return false end
for _, name in ipairs { "MoveForwardStart", "MoveForwardStop", "MoveBackwardStart", "MoveBackwardStop", "StrafeLeftStart",
	"StrafeLeftStop", "StrafeRightStart", "StrafeRightStop", "MouselookStart", "MouselookStop", "JumpOrAscendStart", "AscendStop",
	"SitStandOrDescendStart", "DescendStop", "ToggleAutoRun", "TargetNearestEnemy", "TargetNearestFriend", "TargetUnit",
	"ToggleCharacter", "ToggleSpellBook", "ToggleTalentFrame", "OpenAllBags", "ToggleFrame", "ToggleFriendsFrame",
	"ToggleLFDParentFrame", "ToggleAchievementFrame", "ToggleGameMenu", "CloseAllBags", "ClearCursor", "CloseLoot", "HideUIPanel" } do
	_G[name] = function(...) record(name, ...) end
end
_G.CloseWindows = function()
	record("CloseWindows")
	local had = next(game.windows) ~= nil
	game.windows = {}
	return had
end
_G.StaticPopup_EscapePressed = function()
	record("StaticPopup_EscapePressed")
	if game.popupEscapes then
		_G.StaticPopup1.shown = false
		return true
	end
end
_G.StaticPopup1 = newFrame()
_G.StaticPopup1.shown = false
_G.MAINMENU_BUTTON = "Menu"

-- For holding: time, keys, bindings, cooldowns and the bar buttons a binding clicks.
game.now, game.keys, game.mods, game.bindings, game.other = 100, {}, {}, {}, {}
game.cooldown, game.current, game.repeating, game.override, game.modified = {}, {}, {}, {}, {}
_G.IsModifiedClick = function(what) return game.modified[what] end
_G.GetTime = function() return game.now end
_G.IsShiftKeyDown = function() return game.mods.shift end
_G.IsControlKeyDown = function() return game.mods.ctrl end
_G.IsAltKeyDown = function() return game.mods.alt end
_G.GetBindingKey = function(command) return unpack(game.bindings[command] or {}) end
_G.GetBindingAction = function(key, checkOverride)
	if checkOverride and game.override[key] then return game.override[key] end
	if game.other[key] then return game.other[key] end
	for command, keys in pairs(game.bindings) do
		for _, k in ipairs(keys) do if k == key then return command end end
	end
	return ""
end
_G.GetCurrentKeyBoardFocus = function() return game.focus end
_G.IsAttackAction = function(slot) return game.repeating[slot] == "attack" end
_G.IsAutoRepeatAction = function(slot) return game.repeating[slot] == "auto" end
_G.IsCurrentAction = function(slot) return game.current[slot] end
_G.UnitCastingInfo = function() return game.casting end
_G.UnitChannelInfo = function() return nil end
_G.VehicleMenuBar = newFrame()
_G.VehicleMenuBar.shown = false
_G.BonusActionBarFrame = newFrame()
_G.BonusActionBarFrame.shown = false
for i = 1, 12 do
	_G["ActionButton" .. i] = newFrame()
	_G["ActionButton" .. i].action = i
	_G["MultiBarBottomLeftButton" .. i] = newFrame()
	_G["MultiBarBottomLeftButton" .. i].action = 60 + i
end

-- Interface Options, Combat.
local optionControls = {}
_G.CONTROLTYPE_CHECKBOX = 1
_G.InterfaceOptionsCombatPanel = newFrame()
_G.InterfaceOptionsCombatPanelSelfCastKeyDropDown = newFrame()
_G.BlizzardOptionsPanel_RegisterControl = function(control, panel)
	optionControls[#optionControls + 1] = { control = control, panel = panel }
end

-- ---- pretend controller --------------------------------------------------------------------------------------
local pad = { replaced = {}, connected = true, family = "ltr", lx = 0, ly = 0, rx = 0, ry = 0, front = true, queue = {}, commands = {}, scan = nil }
local driver
local N = {
	SetDriver = function(func) driver = func end,
	Try = function(func, ...)
		local ok, message = pcall(func, ...)
		return ok, message
	end,
	Poll = function() return pad.connected, pad.family, pad.lx, pad.ly, pad.rx, pad.ry, 0, 0, pad.front end,
	Name = function() return "Test Pad" end,
	NextEvent = function()
		local e = table.remove(pad.queue, 1)
		if e then return e[1], e[2] end
	end,
	StickMouse = function(x, y) pad.stickX, pad.stickY = x, y end,
	SetCursor = function(x, y) record("SetCursor", x, y) end,
	MouseButton = function(b, d) record("MouseButton", b, d) end,
	Wheel = function(d) record("Wheel", d) end,
	ScanInteract = function() if pad.scan then return pad.scan, 1, 2 end end,
	Interact = function(hi, lo) record("Interact", hi, lo) end,
	Rumble = function() record("Rumble") end,
	KeyHeld = function(name) return pad.front and game.keys[name] or false end,
	Call = function(func, ...) return func(...) end,
	Global = function(name) return _G[name], not pad.replaced[name] end,
	InWorld = function() return not game.loading end,
	PostCommand = function(text) pad.commands[#pad.commands + 1] = text end,
	NextCommand = function() return table.remove(pad.commands, 1) end,
	Log = function(m) if m:find("^error") then print(m) failures = failures + 1 end end,
	LoadSettings = function() return pad.settings end,
	SaveSettings = function(t) pad.saved = t end,
}
pad.settings = "camera=500\nbogus=3\n"

local G = {}
local before = {}
for key in pairs(_G) do before[key] = true end
for _, file in ipairs { "atlas", "core", "actions", "radial", "cursor", "hud", "world", "hold", "api" } do
	assert(loadfile("lua/" .. file .. ".lua"))(N, G)
end
local Atlas = G.Atlas
for key in pairs(_G) do
	check(before[key] or key == "SLASH_GAMEPAD1" or key == "C_Controller",
		"no new global but the slash command and the addon API: " .. tostring(key))
end
check(driver ~= nil, "the frame function goes to the DLL, not onto a frame anyone can find")
check(#onUpdates == 0, "no OnUpdate scripts")

local function frame(seconds)
	game.now = game.now + (seconds or 0.016)
	driver(seconds or 0.016)
end
local function press(name) pad.queue[#pad.queue + 1] = { name, true } frame() end
local function release(name) pad.queue[#pad.queue + 1] = { name, false } frame() end
local function tap(name) press(name) release(name) end

-- ---- settings ------------------------------------------------------------------------------------------------
check(G.settings.camera == 500, "settings file read")
check(G.settings.bogus == nil, "unknown settings ignored")

-- ---- turning on ----------------------------------------------------------------------------------------------
frame()
check(not G.active, "stays quiet until touched")
tap("EAST")
check(G.active, "a press turns it on")

-- ---- abilities -----------------------------------------------------------------------------------------------
check(called("UseAction", 1), "East on base uses main 1")
clear() tap("LEFT")
check(called("UseAction", 7), "Left on base uses main 7")
clear() press("LT") tap("SOUTH") release("LT")
check(called("UseAction", 8), "LT+South uses main 8")
check(not called("JumpOrAscendStart"), "and doesn't jump")
clear() press("LT") tap("NORTH") release("LT")
check(called("UseAction", 11), "LT+North uses main 11")
clear() press("LT") tap("LEFT") release("LT")
check(called("UseAction", 63), "LT+Left is bottom left 3")
clear() press("RT") tap("SOUTH") release("RT")
check(called("UseAction", 64), "RT+South carries on through bottom left")
clear() press("RT") tap("LEFT") release("RT")
check(called("UseAction", 71), "RT+Left is bottom left 11")
clear() press("LT") press("RT") tap("SOUTH") release("LT") release("RT")
check(called("UseAction", 72), "both triggers + South is bottom left 12")
clear() press("LT") press("RT") tap("LEFT") release("LT") release("RT")
check(called("UseAction", 55), "both triggers + Left is bottom right 7")

game.offset = 1
clear() tap("EAST")
check(called("UseAction", 73), "a stance moves main to its bonus page")
game.offset = 0
game.page = 2
clear() tap("EAST")
check(called("UseAction", 13), "a bar page moves it too")
game.page = 1

-- auto target
game.actions[1] = "fireball"
clear() tap("EAST")
check(called("TargetNearestEnemy"), "harmful spell with no target finds one")
game.target = "enemy"
clear() tap("EAST")
check(not called("TargetNearestEnemy"), "keeps the target it has")
game.target = nil
G.settings.autotarget = 0
clear() tap("EAST")
check(not called("TargetNearestEnemy"), "auto target can be off")
G.settings.autotarget = 1
game.actions[1] = nil

-- ---- jump and interact ---------------------------------------------------------------------------------------
clear() press("SOUTH")
check(called("JumpOrAscendStart"), "South jumps")
release("SOUTH")
check(called("AscendStop"), "and lets go")

pad.scan = "loot"
frame(0.3)
clear() press("SOUTH")
check(called("Interact", 1) and not called("JumpOrAscendStart"), "South loots what's near")
release("SOUTH")
game.combat = true
frame(0.3)
clear() press("SOUTH")
check(called("JumpOrAscendStart") and not called("Interact"), "in combat South jumps again")
release("SOUTH")
game.combat = false
pad.scan = nil
frame(0.3)

-- ---- targeting -----------------------------------------------------------------------------------------------
clear() press("RB") frame(0.1) release("RB")
check(count("TargetNearestEnemy") == 1, "tapping RB cycles enemies")
clear() press("LB") frame(0.1) release("LB")
check(count("TargetNearestFriend") == 1, "tapping LB cycles friends")

clear() press("RB") frame(0.3)
check(called("TargetNearestEnemy", true), "holding RB with no nameplates steps backward")
release("RB")
check(count("TargetNearestEnemy") == 1, "and doesn't also cycle on release")

game.party = true
clear() press("LB") frame(0.3)
check(G.RadialOpen(), "holding LB opens the friends ring")
pad.rx, pad.ry = 0, 1
frame()
pad.rx, pad.ry = 0, 0
release("LB")
check(called("TargetUnit", "player"), "stick up, let go: yourself")
check(not G.RadialOpen(), "ring closes")
check(not called("TargetNearestFriend"), "no cycle as well")

clear() press("LB") frame(0.3)
pad.rx, pad.ry = 0, -1
frame()
pad.rx, pad.ry = 0, 0
release("LB")
check(called("TargetUnit", "party1"), "stick the other way picks the party member")
game.party = nil

clear() press("LB") frame(0.3)
release("LB")
check(not called("TargetUnit"), "letting go without pointing picks nobody")

clear() press("LB") frame(0.3)
tap("EAST")
check(not G.RadialOpen(), "East cancels the ring")
check(not called("UseAction"), "and casts nothing")
release("LB")

-- ---- menu ring -----------------------------------------------------------------------------------------------
clear() tap("START")
check(G.RadialOpen(), "Start opens the menu ring")
pad.rx, pad.ry = 0, 1
frame()
pad.rx, pad.ry = 0, 0
tap("SOUTH")
check(called("ToggleCharacter", "PaperDollFrame"), "South picks Character")
clear() tap("START") tap("START")
check(not G.RadialOpen(), "Start closes it again")

-- ---- moving and camera ---------------------------------------------------------------------------------------
clear() pad.ly = 0.8 frame()
check(count("MoveForwardStart") == 1, "stick forward walks")
check(called("MouselookStart"), "and the character follows the camera")
check(pad.stickX == 500, "camera speed from settings")
frame() frame()
check(count("MoveForwardStart") == 1, "only starts once")
pad.ly = 0.35 frame()
check(not called("MoveForwardStop"), "stays moving in the gap")
pad.ly = 0.1 frame()
check(called("MoveForwardStop"), "stops under it")
pad.ly = 0
clear() pad.lx = -0.9 pad.ly = 0.9 frame()
check(called("StrafeLeftStart") and called("MoveForwardStart"), "diagonals use both")
pad.lx = 0 pad.ly = 0 frame()
check(called("StrafeLeftStop") and called("MoveForwardStop"), "both stop")
frame(0.7) frame()
check(called("MouselookStop"), "mouselook lets go after a moment")
check(pad.stickX == 0, "the stick stops moving the mouse")

G.settings.invert = 1
clear() pad.ry = 0.5 frame()
check(pad.stickY == -500, "invert flips only up and down")
pad.ry = 0 frame(0.7) frame()
G.settings.invert = 0

-- ---- losing focus --------------------------------------------------------------------------------------------
clear() pad.ly = 0.9 frame()
check(called("MoveForwardStart"), "running")
pad.front, pad.ly = false, 0
frame()
check(called("MoveForwardStop"), "alt-tab stops the character")
check(called("MouselookStop"), "and mouselook")
pad.front = true
frame()

-- ---- windows -------------------------------------------------------------------------------------------------
local button = newFrame()
button.cx, button.cy = 100, 400
button.scripts.OnClick = function() end
local button2 = newFrame()
button2.cx, button2.cy = 100, 100
button2.scripts.OnClick = function() end
game.enumerate = { button, button2 }
game.windows.left = {}
clear() frame(0.3)
check(G.mode == "cursor", "a window takes over")
check(not called("SetCursor"), "the cursor waits for mouselook to let go")
frame(0.1)
check(called("SetCursor", 0.1), "the cursor goes to its first button")
clear() tap("EAST")
check(called("CloseWindows"), "East closes")
frame(0.3)
check(G.mode == "world", "closed window gives the controls back")

game.windows.left = {}
frame(0.3)
clear() press("SOUTH")
check(called("MouseButton", "left") and not called("JumpOrAscendStart"), "South clicks")
release("SOUTH")
clear() tap("WEST")
check(called("MouseButton", "right"), "West right-clicks")
check(not called("UseAction"), "abilities wait")
clear() tap("RT")
check(called("Wheel", -1), "triggers scroll")
clear() tap("DOWN")
check(called("SetCursor"), "the D-pad jumps between buttons")
clear() tap("BACK")
check(G.mode == "world", "Back gives the controls back with a window still open")
frame(0.3) frame(0.3)
check(G.mode == "world", "and the open window doesn't take them again")
clear() tap("NORTH")
check(called("UseAction"), "abilities work with it open")
game.windows.left = nil
frame(0.3)
game.windows.left = {}
frame(0.3)
check(G.mode == "cursor", "a window opened later takes over again")
tap("EAST")
frame(0.3)

-- In combat a window doesn't take the abilities away.
game.combat = true
game.windows.left = {}
frame(0.3)
check(G.mode == "world", "no takeover in combat")
game.windows.left = nil
game.combat = false
frame(0.3)

-- Popups are answered, never just hidden.
_G.StaticPopup1.shown = true
game.popupEscapes = true
frame(0.3) frame(0.1)
check(G.mode == "cursor", "a popup takes the cursor")
clear() tap("EAST")
check(called("StaticPopup_EscapePressed") and not _G.StaticPopup1.shown, "East answers it as Escape does")
frame(0.3)
_G.StaticPopup1.shown = true
game.popupEscapes = false
frame(0.3) frame(0.1)
clear() tap("EAST")
check(_G.StaticPopup1.shown, "release spirit isn't dismissed")
check(G.mode == "world", "and East gives the controls back rather than sticking")
_G.StaticPopup1.shown = false
frame(0.3)

clear() tap("BACK")
check(G.mode == "cursor", "Back asks for the cursor")
frame(0.3)
check(G.mode == "cursor", "and it stays with no window")
tap("EAST")
check(G.mode == "world", "East ends it")

-- A jump held while a window opens still lets go.
clear() press("SOUTH")
game.windows.left = {}
frame(0.3)
check(G.mode == "cursor", "window opened mid jump")
release("SOUTH")
check(called("AscendStop"), "the jump still lets go")
check(not called("MouseButton"), "and no stray click")
tap("BACK")
game.windows.left = nil
frame(0.3)

-- A click held when the mode ends lets go.
tap("BACK")
clear() press("SOUTH")
G.LeaveCursor()
check(called("MouseButton", "left"), "a held click is released")
release("SOUTH")

-- Ring in cursor mode: the stick points at the ring, it doesn't drag the cursor.
tap("BACK")
frame()
check(pad.stickX ~= 0, "cursor mode drives the cursor")
press("START")
frame()
check(pad.stickX == 0, "the ring takes the stick")
release("START")
tap("START")
frame()
tap("BACK")
frame()

-- Holding something when the ring opens.
clear() press("SOUTH") press("RB") frame(0.3)
game.party = nil
release("SOUTH")
check(called("AscendStop"), "a jump held into a ring still lets go")
if G.RadialOpen() then release("RB") else release("RB") end
clear() press("LB") frame(0.3)
check(G.RadialOpen(), "ring open")
pad.rx, pad.ry = 0, 1
frame()
pad.rx, pad.ry = 0, 0
pad.front = false
release("LB")
check(not called("TargetUnit"), "alt-tab with a ring open picks nobody")
check(not G.RadialOpen(), "and closes it")
pad.front = true
frame()

-- ---- placing spells ------------------------------------------------------------------------------------------
game.castTargets = true
clear() tap("EAST")
check(G.mode == "aim", "a ground spell starts aiming")
check(pad.stickX ~= 0, "the stick moves the reticle")
game.castTargets = false
press("SOUTH")
check(called("MouseButton", "left"), "South places it")
game.targeting = false
release("SOUTH")
frame()
check(G.mode == "world", "and aiming ends")
frame()

game.castTargets = true
clear() tap("EAST")
game.castTargets = false
tap("EAST")
check(called("SpellStopTargeting") and G.mode == "world", "East cancels aiming")

game.castTargets = true
clear() tap("EAST")
game.castTargets = false
press("SOUTH")
game.targeting = false
frame()
check(G.mode == "world", "a spell that resolves on the press ends aiming")
check(count("MouseButton") == 2, "and the button still comes back up")
release("SOUTH")
check(count("MouseButton") == 2, "with no stray extra")

-- ---- controller types ----------------------------------------------------------------------------------------
pad.family = "shp"
frame()
check(G.family == "shp", "a PlayStation pad changes the art")
for family, set in pairs(Atlas) do
	for _, name in ipairs { "SOUTH", "EAST", "WEST", "NORTH", "UP", "RIGHT", "DOWN", "LEFT", "LB", "RB", "LT", "RT", "START", "BACK", "L3", "R3" } do
		check(set[name] ~= nil, family .. " has " .. name)
	end
end
check(Atlas.rev.SOUTH[2] ~= Atlas.rev.EAST[2] or Atlas.rev.SOUTH[4] ~= Atlas.rev.EAST[4], "Nintendo's buttons differ")
pad.family = "ltr"
frame()

-- ---- loading screens ----------------------------------------------------------------------------------------
local eventFrame
for _, f in ipairs(frames) do
	local registered = rawget(f, "events")
	if f.scripts.OnEvent and registered and registered.PLAYER_LEAVING_WORLD then eventFrame = f end
end
check(eventFrame ~= nil, "listens for loading screens")
frame()
clear() pad.ly = 0.9 frame()
check(called("MoveForwardStart"), "running into a loading screen")
game.loading = true
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LEAVING_WORLD")
check(not called("MoveForwardStop"), "the event alone calls nothing protected")
frame()
check(called("MoveForwardStop") and called("MouselookStop"), "the frame function stops it")
clear() frame() frame()
check(not called("MoveForwardStart"), "and nothing starts while loading")
tap("EAST")
check(not called("UseAction"), "no abilities through a loading screen")
game.loading = false
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
frame()
check(called("MoveForwardStart"), "still holding the stick after loading: runs again")
pad.ly = 0 frame() frame(0.7) frame()

-- ---- unplugged -----------------------------------------------------------------------------------------------
clear() pad.ly = 0.9 frame()
press("LT")
pad.connected, pad.ly = false, 0
frame()
check(called("MoveForwardStop"), "unplugging stops the character")
check(not G.active, "and hides everything")
check(G.Layer() == "BASE", "no layer stays held")
pad.connected = true
frame()
check(not G.active, "plugging back in waits for a press")

-- ---- switched off --------------------------------------------------------------------------------------------
SlashCmdList.GAMEPAD("off")
frame()
clear() tap("EAST")
check(not called("UseAction"), "/controller off stops everything")
check(pad.saved and pad.saved:find("enabled=0"), "and is remembered")
SlashCmdList.GAMEPAD("on")
frame()
clear() tap("EAST")
check(called("UseAction"), "/controller on brings it back")
SlashCmdList.GAMEPAD("camera 700")
check(G.settings.camera ~= 700, "a slash command never writes our tables itself")
frame()
check(G.settings.camera == 700, "/controller camera 700")
SlashCmdList.GAMEPAD("")
frame()
check(called("say"), "help text")

-- ---- the addon API ------------------------------------------------------------------------------------------
do
	local api = C_Controller
	check(type(api) == "table", "C_Controller is there for addons")
	local function binding(bar, index) return table.concat({ api.GetBinding(bar, index) }, " ") end
	check(binding("main", 1) == "EAST BASE", "main 1 is East")
	check(binding("main", 7) == "LEFT BASE", "main 7 is Left")
	check(binding("main", 8) == "SOUTH LT", "main 8 is LT+South")
	check(binding("bottomleft", 3) == "LEFT LT", "bottom left 3 is LT+Left")
	check(binding("bottomleft", 12) == "SOUTH BOTH", "bottom left 12 is both triggers + South")
	check(binding("bottomright", 7) == "LEFT BOTH", "bottom right 7 is both triggers + Left")
	check(api.GetBinding("bottomright", 8) == nil, "bottom right 8 has no button")
	check(api.GetBinding("right", 1) == nil, "other bars have none")
	local path, l, r, t, b = api.GetGlyph("SOUTH")
	local cell = Atlas.ltr.SOUTH
	check(path == "Interface\\GamePad\\ltr" and l == cell[2] and b == cell[5], "glyph for the pad in use")
	check(api.GetGlyph("NOPE") == nil, "no glyph for a made-up button")
	check(type(api.GetBinding("main", 1)) == "string", "plain values, never our tables")

	tap("EAST")
	local connected, active, family, layer, mode = api.GetState()
	check(connected and active and family == "ltr" and layer == "BASE" and mode == "world", "state while in use")
	press("LT")
	check(select(4, api.GetState()) == "LT", "the held layer")
	release("LT")

	check(G.hudFrame:IsShown(), "the cross shows while in use")
	api.SetBarsShown(true)
	check(G.hudFrame:IsShown(), "a request waits for the next frame")
	frame()
	check(not G.hudFrame:IsShown(), "an addon showing the abilities on its bars hides the cross")
	tap("EAST")
	check(not G.hudFrame:IsShown(), "and it stays hidden while playing")
	api.SetBarsShown(false)
	frame()
	check(G.hudFrame:IsShown(), "and comes back when the addon stops")
	check(not pad.saved or not pad.saved:find("ownbars"), "not saved")

	press("WEST")
	api.Rest()
	frame()
	check(not G.active and not select(2, api.GetState()), "Rest hands back to keyboard and mouse")
	check(not G.held.WEST, "and lets go of what was held")
	check(not G.hudFrame:IsShown(), "with the cross gone")
	release("WEST")
	tap("EAST")
	check(G.active, "the next press takes over again")

	-- Rest out of a cursor the player asked for: a window opened later still takes it and gives it back.
	tap("BACK")
	check(G.mode == "cursor", "Back gives the cursor")
	api.Rest()
	frame()
	check(G.mode == "world" and not G.active, "Rest leaves the cursor")
	tap("EAST")
	game.windows.left = {}
	frame(0.3) frame(0.1)
	check(G.mode == "cursor", "a window opened after Rest takes the cursor")
	game.windows.left = nil
	frame(0.3)
	check(G.mode == "world", "and gives it back when it closes")

	-- Rest while placing a spell drops the spell, so the next press isn't aiming blind.
	game.castTargets = true
	clear() tap("EAST")
	game.castTargets = false
	check(G.mode == "aim", "aiming")
	api.Rest()
	clear() frame()
	check(called("SpellStopTargeting") and G.mode == "world" and not game.targeting, "Rest while aiming cancels it")
	tap("EAST")

	SlashCmdList.GAMEPAD("off")
	frame()
	check(not (api.GetState()), "turned off counts as no controller")
	SlashCmdList.GAMEPAD("on")
	frame()
	check((api.GetState()), "and on again as plugged in")
	tap("EAST")

	api.SetBarsShown(true)
	SlashCmdList.GAMEPAD("camera 650")
	frame()
	check(G.ownBars and G.settings.camera == 650, "an addon request and a slash command in one frame both arrive")
	api.SetBarsShown(false)
	frame()
end

-- ---- holding to keep casting ---------------------------------------------------------------------------------
do
	local function wait(seconds)
		for _ = 1, math.floor(seconds / 0.05 + 0.5) do frame(0.05) end
	end
	-- What the client's binding does with a bar key: marks the button on the way down, clicks it on the way up if it's
	-- still marked.
	local function keyDown(key, button)
		game.keys[key] = true
		if button:GetButtonState() == "NORMAL" then rawset(button, "state", "PUSHED") end
		frame()
	end
	local function keyUp(key, button)
		game.keys[key] = nil
		local clicked = button:GetButtonState() == "PUSHED"
		rawset(button, "state", "NORMAL")
		frame()
		return clicked
	end
	local function castAt(slot) return count("UseAction") > 0 and called("UseAction", slot) end
	local events
	for _, f in ipairs(frames) do
		local registered = rawget(f, "events")
		if registered and registered.UI_ERROR_MESSAGE then events = f end
	end
	check(events ~= nil, "hold listens for the game's error messages")

	local button3 = _G.ActionButton3
	game.bindings.ACTIONBUTTON3 = { "3" }
	game.bindings.MULTIACTIONBAR1BUTTON2 = { "SHIFT-E" }
	game.bindings.ACTIONBUTTON4 = { "E" }
	events.scripts.OnEvent(events, "UPDATE_BINDINGS")
	check(G.settings.hold == 0, "hold is off unless asked for")
	game.gcd = 1.5

	clear() keyDown("3", button3) wait(1)
	check(not called("UseAction"), "off: holding a key does nothing of ours")
	check(keyUp("3", button3), "off: the client still casts on the way up")

	SlashCmdList.GAMEPAD("hold 1")
	frame()
	check(G.settings.hold == 1 and pad.saved:find("hold=1"), "/controller hold 1 turns it on and saves it")

	clear() keyDown("3", button3) wait(0.1)
	check(not called("UseAction"), "a tap isn't a hold")
	check(keyUp("3", button3), "a tap is left to the client")

	clear() keyDown("3", button3) wait(0.3)
	check(count("UseAction") == 1 and castAt(3), "held: used once it counts as holding")
	check(button3:GetButtonState() == "NORMAL", "and the button is unmarked")
	clear() wait(1)
	check(not called("UseAction"), "waits for the cooldown")
	wait(0.6)
	check(count("UseAction") == 1 and castAt(3), "used again when it's ready")
	game.gcd = nil
	wait(1.6)
	clear() wait(0.5)
	check(not called("UseAction"), "a use that showed no cooldown, cast or 'on' waits a second")
	wait(0.6)
	check(count("UseAction") == 1, "then tries again")
	clear() wait(0.3)
	check(count("UseAction") == 0, "never faster than that")
	game.gcd = 1.5
	clear()
	check(not keyUp("3", button3), "letting go doesn't cast once more")
	wait(2)
	check(not called("UseAction"), "let go: stops")

	-- Errors slow it down, however long the server takes to send them.
	game.gcd = 0.5
	clear() keyDown("3", button3) wait(0.3)
	check(count("UseAction") == 1, "held again")
	wait(0.4)
	events.scripts.OnEvent(events, "UI_ERROR_MESSAGE")
	clear() wait(0.5)
	check(not called("UseAction"), "an error after a try waits longer than the cooldown")
	wait(0.6)
	check(called("UseAction"), "then tries again")
	keyUp("3", button3)
	game.gcd = 1.5
	wait(2)

	-- Things that must never be used twice.
	for _, case in ipairs { { "current", true, "something already on" }, { "repeating", "auto", "Auto Shot" },
		{ "repeating", "attack", "auto attack" }, { "actions", "mount", "a mount" } } do
		game[case[1]][3] = case[2]
		clear() keyDown("3", button3) wait(1)
		check(not called("UseAction"), "never repeats " .. case[3])
		keyUp("3", button3)
		game[case[1]][3] = nil
	end
	game.casting = "Frostbolt"
	clear() keyDown("3", button3) wait(1)
	check(not called("UseAction"), "never cuts into another cast")
	keyUp("3", button3)
	game.casting = nil
	wait(2)

	-- Modifiers.
	game.mods.shift = true
	clear() keyDown("E", _G.MultiBarBottomLeftButton2) wait(0.3)
	check(castAt(62), "Shift-E uses its own binding, bottom left 2")
	keyUp("E", _G.MultiBarBottomLeftButton2)
	game.bindings.MULTIACTIONBAR1BUTTON2 = nil
	events.scripts.OnEvent(events, "UPDATE_BINDINGS")
	wait(2)
	clear() keyDown("E", _G.ActionButton4) wait(0.3)
	check(castAt(4), "Shift-E with nothing of its own uses E, as the client does")
	keyUp("E", _G.ActionButton4)
	wait(2)
	game.other["SHIFT-E"] = "TOGGLEBAG1"
	clear() keyDown("E", _G.ActionButton4) wait(0.5)
	check(not called("UseAction"), "but not when Shift-E is bound to something else")
	keyUp("E", _G.ActionButton4)
	game.other["SHIFT-E"] = nil
	game.mods.shift = nil

	game.mods.alt, game.modified.SELFCAST = true, true
	clear() keyDown("3", button3) wait(0.3)
	local unit
	for _, c in ipairs(calls) do if c[1] == "UseAction" then unit = c[3] end end
	check(castAt(3) and unit == "player", "Alt with a plain key's binding casts on yourself, as the button would")
	keyUp("3", button3)
	game.mods.alt, game.modified.SELFCAST = nil, nil
	wait(2)

	clear() keyDown("3", button3) wait(0.2)
	game.mods.shift = true
	wait(0.2)
	game.mods.shift = nil
	wait(0.2)
	check(not called("UseAction"), "a modifier changing mid-hold starts the hold over")
	keyUp("3", button3)

	-- Another addon's bars took the key over.
	game.override["3"] = "CLICK BT4Button3:LeftButton"
	clear() keyDown("3", button3) wait(1)
	check(not called("UseAction"), "a key another bar addon took over is left alone")
	keyUp("3", button3)
	game.override["3"] = "CLICK DragonUI_KeyPressButton_3:LeftButton"
	clear() keyDown("3", button3) wait(0.3)
	check(castAt(3), "DragonUI's key-down casting clicks the same button, so it's held as usual")
	keyUp("3", button3)
	game.override["3"] = nil
	wait(2)

	-- Where a key must do nothing.
	game.focus = {}
	clear() keyDown("3", button3) wait(1)
	check(not called("UseAction"), "typing in chat")
	keyUp("3", button3)
	game.focus = nil
	clear() keyDown("3", button3) wait(0.3)
	check(count("UseAction") == 1, "held")
	game.focus = {}
	clear() wait(2)
	check(not called("UseAction"), "chat opened mid-hold: stops")
	game.focus = nil
	keyUp("3", button3)
	pad.front = false
	clear() keyDown("3", button3) wait(1)
	check(not called("UseAction"), "game not in front")
	keyUp("3", button3)
	pad.front = true

	_G.BonusActionBarFrame.shown = true
	_G.BonusActionButton3 = newFrame()
	_G.BonusActionButton3.action = 75
	clear() keyDown("3", _G.BonusActionButton3) wait(0.3)
	check(castAt(75), "a stance bar: the button the binding clicks, with its slot")
	keyUp("3", _G.BonusActionButton3)
	_G.BonusActionBarFrame.shown = false
	wait(2)

	-- The controller.
	G.SetMode("world")
	clear() press("EAST")
	check(count("UseAction") == 1 and castAt(1), "a controller press uses it at once")
	wait(1)
	check(count("UseAction") == 1, "held: waits for the cooldown")
	wait(0.6)
	check(count("UseAction") == 2, "then again")
	release("EAST")
	clear() wait(2)
	check(not called("UseAction"), "let go: stops")

	press("LT") press("EAST") release("LT")
	clear() wait(1.6)
	check(castAt(9) and not called("UseAction", 1), "the layer it was pressed on stays, trigger let go or not")
	release("EAST")
	wait(2)

	SlashCmdList.GAMEPAD("hold 0")
	frame()
	clear() press("EAST") wait(1)
	check(count("UseAction") == 1, "off: a held controller button is used once")
	release("EAST")
	game.gcd = nil
end

-- ---- the setting in Interface Options ---------------------------------------------------------------------------
do
	check(#optionControls == 1 and optionControls[1].panel == _G.InterfaceOptionsCombatPanel,
		"hold has a box in Interface, Combat")
	local box = optionControls[1].control
	check(box.template == "InterfaceOptionsCheckButtonTemplate" and box.type == CONTROLTYPE_CHECKBOX, "a stock checkbox")
	check(box.frameName ~= nil, "named, so the template's label exists")
	check(box.value == "0" and box:GetValue() == "0" and box.defaultValue == "0", "off, and off by default")

	local function wait(seconds)
		for _ = 1, math.floor(seconds / 0.05 + 0.5) do frame(0.05) end
	end
	-- Copies of the stock calls (InterfaceOptionsPanels.lua, OptionsPanelTemplates.lua), branch for branch.
	local function click(on) -- InterfaceOptionsPanel_CheckButton_Update
		box:SetChecked(on)
		box.value = on and "1" or "0"
		if box.setFunc then box.setFunc(box.value) end
	end
	local function open() -- InterfaceOptionsPanel_Refresh: BlizzardOptionsPanel_CheckButton_Refresh, then oldValue
		local value = tostring(box:GetValue())
		box:SetChecked(value == "1")
		box.oldValue = box.value
	end
	local function cancel() -- InterfaceOptionsPanel_Cancel
		if box.oldValue then
			if box.value and box.value ~= box.oldValue then box:SetValue(box.oldValue) end
		elseif box.value then
			if box:GetValue() ~= box.value then box:SetValue(box.value) end
		end
		if box.setFunc then box.setFunc(box:GetValue()) end
	end
	local function okay() -- BlizzardOptionsPanel_OkayControl, no newValue
		if box.value and box:GetValue() ~= box.value then box:SetValue(box.value) end
	end
	local function defaults() -- InterfaceOptionsPanel_Default
		if box.defaultValue and box.value ~= box.defaultValue then
			box:SetValue(box.defaultValue)
			box.value = box.defaultValue
		end
		if box.setFunc then box.setFunc(box:GetValue()) end
	end

	open()
	check(box:GetChecked() == false, "opens unticked")
	clear() click(true)
	frame()
	check(G.settings.hold == 1 and pad.saved:find("hold=1"), "ticking the box turns it on and saves it")
	check(not called("say"), "without a chat message")
	okay()
	frame()
	check(G.settings.hold == 1, "Okay keeps it")

	open()
	check(box:GetChecked() == true, "opens ticked")
	click(false)
	cancel()
	frame()
	check(G.settings.hold == 1, "untick then Cancel in the same frame: still on")
	wait(1)
	open()
	click(false)
	frame()
	cancel()
	frame()
	check(G.settings.hold == 1, "untick, a frame, then Cancel: back on")
	wait(1)

	pad.saved = nil
	open()
	cancel()
	frame()
	check(#pad.commands == 0 and pad.saved == nil, "closing with nothing changed sends nothing")

	SlashCmdList.GAMEPAD("hold 0")
	frame()
	okay()
	frame()
	check(G.settings.hold == 0, "a chat change and then Okay: Okay doesn't put the old value back")
	open()
	check(box:GetChecked() == false and box.value == "0", "and the box shows it on the next open")

	click(true)
	frame()
	wait(1)
	defaults()
	frame()
	check(G.settings.hold == 0, "Defaults turns it off")

	-- A request the DLL dropped (its queue was full) doesn't stick to the box.
	local post = N.PostCommand
	N.PostCommand = function() end
	click(true)
	wait(1)
	open()
	check(box:GetChecked() == false, "a lost request: the box shows the real setting again")
	N.PostCommand = post
	SlashCmdList.GAMEPAD("quiet nonsense")
	clear() frame()
	check(not called("say"), "quiet stays quiet, help text too")
end

-- ---- the cross's two styles -----------------------------------------------------------------------------------
do
	local api = C_Controller
	local parts = G.hudParts
	tap("EAST")
	check(G.Style() == "wow" and api.GetStyle() == "wow", "WoW Forever's cross by default")
	check(G.hudFrame:IsShown() and parts.wow:IsShown() and not parts.xiv:IsShown(), "and it's the one on screen")

	clear()
	SlashCmdList.GAMEPAD("style xiv")
	frame()
	check(G.settings.style == 1 and pad.saved:find("style=1"), "/controller style xiv picks the cross hotbar, saved")
	check(called("say"), "and says so")
	check(parts.xiv:IsShown() and not parts.wow:IsShown(), "the cross hotbar replaces the cross")
	local sets = parts.sets
	check(sets.MIDDLE.layer == "BASE" and sets.LT.layer == "LT" and sets.RT.layer == "RT", "LT, the buttons, RT")
	check(sets.MIDDLE.frame.alpha == 1 and sets.LT.frame.alpha < 1 and sets.RT.frame.alpha < 1,
		"nothing held: the buttons' own set stands out")
	check(sets.MIDDLE.buttons.EAST.w > sets.LT.buttons.EAST.w, "and is the big one")
	check(not sets.MIDDLE.labels[1].shown and sets.LT.labels[1].shown and not sets.LT.labels[2].shown,
		"each trigger's set is labelled with its trigger")

	press("LT")
	check(sets.LT.frame.alpha == 1 and sets.MIDDLE.frame.alpha < 1, "holding LT brings its set forward")
	check(sets.LT.buttons.EAST.w > sets.MIDDLE.buttons.EAST.w, "at full size")
	local function middle(set) return (set.buttons.LEFT.point[2] + set.buttons.EAST.point[2]) / 2 end
	local ltMiddle = middle(sets.LT)
	press("RT")
	check(sets.MIDDLE.layer == "BOTH" and sets.MIDDLE.frame.alpha == 1, "both triggers bring their set to the middle")
	check(sets.LT.frame.alpha < 1 and sets.RT.frame.alpha < 1, "with LT's and RT's faint")
	check(sets.MIDDLE.labels[1].shown and sets.MIDDLE.labels[2].shown, "labelled LT and RT")
	release("RT")
	release("LT")
	check(sets.MIDDLE.layer == "BASE" and sets.MIDDLE.frame.alpha == 1, "letting go puts the buttons' set back")
	check(math.abs(middle(sets.LT) - ltMiddle) < 0.01 and ltMiddle < middle(sets.MIDDLE)
		and middle(sets.MIDDLE) < middle(sets.RT), "sets grow in place: LT left, RT right")

	clear()
	api.SetStyle("bogus")
	frame()
	check(G.settings.style == 1, "a made-up style is ignored")
	api.SetStyle("wow")
	check(G.settings.style == 1, "an addon's pick waits for the next frame")
	frame()
	check(G.settings.style == 0 and api.GetStyle() == "wow" and pad.saved:find("style=0"), "an addon can pick the style")
	check(not called("say"), "quietly")
	check(parts.wow:IsShown() and not parts.xiv:IsShown(), "and the cross is back")
	SlashCmdList.GAMEPAD("style XIV")
	frame()
	check(G.settings.style == 1, "in any case")
	SlashCmdList.GAMEPAD("style 0")
	frame()
	SlashCmdList.GAMEPAD("style 1")
	frame()
	check(G.settings.style == 1, "by number too")
	clear()
	SlashCmdList.GAMEPAD("style plaid")
	frame()
	check(G.settings.style == 1 and called("say"), "an unknown style says what there is")
	SlashCmdList.GAMEPAD("style wow")
	frame()
end

-- ---- an addon replaced a function before we loaded ------------------------------------------------------------
do
	local viaCall = 0
	local realCall = N.Call
	N.Call = function(...)
		viaCall = viaCall + 1
		return realCall(...)
	end
	pad.replaced.Fake = true
	_G.Fake = function() return "addon" end
	local result = G.Protect("Fake")()
	check(result == "addon" and viaCall == 0, "a replaced function runs as the addon's own, never through Call")
	_G.Clean = function() return "game" end
	result = G.Protect("Clean")()
	check(result == "game" and viaCall == 1, "a clean one goes through Call")
	check(G.Protect("NoSuchFunction")() == nil, "a missing one does nothing")
	N.Call = realCall
	_G.Fake, _G.Clean = nil, nil
end

print(checks .. " checks, " .. failures .. " failures")
os.exit(failures == 0 and 0 or 1)
