-- The controller's main loop and button routing. Runs from inside the DLL as the client's own code, so what it does
-- is what a key binding could do, in combat too. Nothing here is an addon. The DLL hands each file these two tables as
-- arguments and there are no globals, so addons can't reach any of it: not to change it, and not to borrow its way
-- of calling protected functions.
local N, G = ...

local DEFAULTS = {
	camera = 900,      -- pixels per second at full tilt
	cursor = 1000,
	invert = 0,        -- 1 flips the camera's up and down
	hud = 1,
	autotarget = 1,    -- a harmful spell with no enemy targeted picks the nearest one first
	autocursor = 1,    -- windows that open take the cursor to their first button
	rumble = 1,
	hold = 0,          -- 1: holding an ability's button or key keeps using it (hold.lua)
	enabled = 1,
}

-- A protected game function, by name, wrapped to run clean; see l_call in main.c. If an addon has replaced it, the
-- replacement gets no favours: it runs as the addon's own code, and the client decides what that may do.
function G.Protect(name)
	local func, clean = N.Global(name)
	if not func then
		N.Log("missing: " .. name)
		return function() end
	end
	if not clean then
		N.Log("replaced by an addon: " .. name)
		return func
	end
	return function(...)
		return N.Call(func, ...)
	end
end

G.settings = {}
for key, value in pairs(DEFAULTS) do G.settings[key] = value end

local function LoadSettings()
	local text = N.LoadSettings()
	if not text then return end
	for key, value in string.gmatch(text, "(%w+)=(%-?[%d%.]+)") do
		if DEFAULTS[key] then G.settings[key] = tonumber(value) end
	end
end

function G.SaveSettings()
	local lines = {}
	for key in pairs(DEFAULTS) do
		lines[#lines + 1] = key .. "=" .. tostring(G.settings[key])
	end
	table.sort(lines)
	N.SaveSettings(table.concat(lines, "\n") .. "\n")
end

-- An error in here is logged, not thrown at the player, and can't stop the next frame.
local reported = {}
function G.Safe(what, func, ...)
	local ok, message = N.Try(func, ...)
	if not ok then
		local text = what .. ": " .. tostring(message)
		if not reported[text] then
			reported[text] = true
			N.Log("error: " .. text)
		end
	end
	return ok, message
end

G.mode = "world"     -- "world", "cursor" (working a window), "aim" (placing a spell)
G.active = false     -- the player has touched the controller since it was connected
G.connected = false
G.family = "ltr"
G.held = {}
G.lx, G.ly, G.rx, G.ry = 0, 0, 0, 0
G.listeners = {}

function G.Listen(name, func)
	local list = G.listeners[name]
	if not list then
		list = {}
		G.listeners[name] = list
	end
	list[#list + 1] = func
end

function G.Fire(name, ...)
	local list = G.listeners[name]
	if list then
		for i = 1, #list do G.Safe(name, list[i], ...) end
	end
end

function G.SetActive(active)
	if G.active ~= active then
		G.active = active
		G.Fire("active", active)
	end
end

function G.SetMode(mode)
	if G.mode ~= mode then
		local previous = G.mode
		G.mode = mode
		G.Fire("mode", mode, previous)
	end
end

function G.Layer()
	if G.held.LT and G.held.RT then return "BOTH" end
	if G.held.LT then return "LT" end
	if G.held.RT then return "RT" end
	return "BASE"
end

local function ReleaseEverything()
	for name in pairs(G.held) do
		G.held[name] = nil
		G.Safe("release", G.OnButton, name, false)
	end
	G.Fire("release")
end

-- Set by the other files; each returns true when it used the press.
G.handlers = { radial = nil, cursor = nil, aim = nil, world = nil }

function G.OnButton(name, down)
	local h = G.handlers
	if h.radial and h.radial(name, down) then return end
	if G.mode == "cursor" and h.cursor and h.cursor(name, down) then return end
	if G.mode == "aim" and h.aim and h.aim(name, down) then return end
	if h.world then h.world(name, down) end
end

local function Frame(elapsed)
	local connected, family, lx, ly, rx, ry, lt, rt, inFront = N.Poll()
	G.lx, G.ly, G.rx, G.ry, G.lt, G.rt = lx, ly, rx, ry, lt, rt
	G.inFront = inFront

	if family ~= G.family then
		G.family = family
		G.Fire("family", family)
	end
	if connected ~= G.connected then
		G.connected = connected
		N.Log(connected and ("controller in use: " .. tostring(N.Name())) or "no controller")
		if not connected then
			ReleaseEverything()
			G.SetActive(false)
		end
	end

	while true do
		local command = N.NextCommand()
		if not command then break end
		G.Safe("command", G.Command, command)
	end

	while true do
		local name, down = N.NextEvent()
		if not name then break end
		if G.settings.enabled == 1 then
			if down then
				G.held[name] = true
				G.SetActive(true)
			else
				G.held[name] = nil
			end
			G.Safe(name, G.OnButton, name, down)
		end
	end

	if G.settings.enabled == 1 and G.active then
		G.Fire("update", elapsed, inFront)
	end
	-- Every frame, with or without a controller: holding a key works for everyone.
	G.Fire("tick", elapsed, inFront)
end

N.SetDriver(function(elapsed)
	G.Safe("frame", Frame, elapsed)
end)

SLASH_GAMEPAD1 = "/controller"
-- Only hands the text on. See l_post_command in main.c.
SlashCmdList["GAMEPAD"] = function(text)
	N.PostCommand(text)
end

function G.Command(text)
	local key, value = string.match(text, "^(%S*)%s*(%S*)")
	local function say(message)
		DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffController:|r " .. message)
	end
	if key == "on" or key == "off" then
		G.settings.enabled = (key == "on") and 1 or 0
		if key == "off" then
			ReleaseEverything()
			G.SetActive(false)
		end
		G.SaveSettings()
		say(key == "on" and "on." or "off. /controller on turns it back on.")
	elseif key == "rest" then
		-- From C_Controller.Rest: back to keyboard and mouse until the next button press. Not saved, nothing said.
		-- Releases first: they go through the cursor and aim handlers, which need the mode they started in.
		ReleaseEverything()
		if G.mode == "cursor" then
			-- Forgets why the cursor was on, so a window opened later still gets it and gives it back.
			G.LeaveCursor(true)
		elseif G.mode == "aim" then
			G.StopTargeting()
			G.SetMode("world")
		end
		G.SetActive(false)
	elseif key == "ownbars" then
		-- From C_Controller.SetBarsShown: an addon draws the abilities on its own bars, so the cross stays hidden.
		-- Not saved: the addon says it again after a reload.
		G.ownBars = value == "1"
		G.Fire("settings", "ownbars")
	elseif DEFAULTS[key] and key ~= "enabled" and tonumber(value) then
		G.settings[key] = tonumber(value)
		G.SaveSettings()
		G.Fire("settings", key)
		say(key .. " is now " .. value .. ".")
	else
		say(G.connected and ("using " .. tostring(N.Name()) .. ".") or "no controller found.")
		say("/controller on | off | camera 900 | cursor 1000 | invert 0-1 | hud 0-1 | autotarget 0-1 | autocursor 0-1 | rumble 0-1 | hold 0-1")
	end
end

LoadSettings()
N.Log("core loaded, secure=" .. tostring(issecure()))
