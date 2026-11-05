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
function FrameMeta.GetChildren() return end
function FrameMeta.GetRegions() return end
local function newFrame()
	local f = setmetatable({ scripts = {}, shown = true }, FrameMeta)
	frames[#frames + 1] = f
	return f
end

_G.CreateFrame = function() return newFrame() end
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
_G.UseAction = function(slot) record("UseAction", slot) if game.castTargets then game.targeting = true end end
_G.SpellIsTargeting = function() return game.targeting end
_G.SpellStopTargeting = function() record("SpellStopTargeting") game.targeting = false end
_G.GetActionInfo = function(slot) return game.actions[slot] and "spell", game.actions[slot] end
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
_G.GetActionCooldown = function() return 0, 0, 1 end
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

-- ---- pretend controller --------------------------------------------------------------------------------------
local pad = { replaced = {}, connected = true, family = "ltr", lx = 0, ly = 0, rx = 0, ry = 0, front = true, queue = {}, scan = nil }
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
	Call = function(func, ...) return func(...) end,
	Global = function(name) return _G[name], not pad.replaced[name] end,
	InWorld = function() return not game.loading end,
	PostCommand = function(text) pad.command = text end,
	NextCommand = function()
		local c = pad.command
		pad.command = nil
		return c
	end,
	Log = function(m) if m:find("^error") then print(m) failures = failures + 1 end end,
	LoadSettings = function() return pad.settings end,
	SaveSettings = function(t) pad.saved = t end,
}
pad.settings = "camera=500\nbogus=3\n"

local G = {}
local before = {}
for key in pairs(_G) do before[key] = true end
for _, file in ipairs { "atlas", "core", "actions", "radial", "cursor", "hud", "world" } do
	assert(loadfile("lua/" .. file .. ".lua"))(N, G)
end
local Atlas = G.Atlas
for key in pairs(_G) do
	check(before[key] or key == "SLASH_GAMEPAD1", "no new global but the slash command: " .. tostring(key))
end
check(driver ~= nil, "the frame function goes to the DLL, not onto a frame anyone can find")
check(#onUpdates == 0, "no OnUpdate scripts")

local function frame(seconds)
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
for _, f in ipairs(frames) do if f.scripts.OnEvent then eventFrame = f end end
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
