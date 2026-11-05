-- Working the game's windows. The right stick drives the real mouse cursor and the D-pad jumps it between buttons,
-- so every window works, addons' included, with nothing to change in them.
local N, G = ...

local SpellStopTargeting = G.Protect("SpellStopTargeting")
local ClearCursor = G.Protect("ClearCursor")
local CloseAllBags = G.Protect("CloseAllBags")
local CloseWindows = G.Protect("CloseWindows")
local CloseLoot = G.Protect("CloseLoot")
local StaticPopup_EscapePressed = G.Protect("StaticPopup_EscapePressed")
local HideUIPanel = G.Protect("HideUIPanel")

local SCROLL_FIRST = 0.35
local SCROLL_REPEAT = 0.12

local function ScreenSize()
	local scale = UIParent:GetEffectiveScale()
	return GetScreenWidth() * scale, GetScreenHeight() * scale
end

local function CursorPosition()
	local x, y = GetCursorPosition()
	return x, y
end

local function Candidates()
	local result = {}
	local width, height = ScreenSize()
	local frame = EnumerateFrames()
	while frame do
		if frame:IsVisible() and frame:IsMouseEnabled() and frame:HasScript("OnClick") and frame:GetScript("OnClick")
			and not frame.action then
			local x, y = frame:GetCenter()
			if x then
				local scale = frame:GetEffectiveScale()
				local fx, fy = x * scale, y * scale
				local w, h = frame:GetWidth() * scale, frame:GetHeight() * scale
				if fx > 0 and fy > 0 and fx < width and fy < height and w >= 6 and h >= 6 then
					result[#result + 1] = { x = fx, y = fy, strata = frame:GetFrameStrata() }
				end
			end
		end
		frame = EnumerateFrames(frame)
	end
	return result
end

local function MoveTo(target)
	local width, height = ScreenSize()
	N.SetCursor(target.x / width, target.y / height)
end

local DIRECTIONS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

-- The nearest button that way, with straight ahead counting for more than off to the side.
function G.SnapChoose(list, fromX, fromY, name)
	local direction = DIRECTIONS[name]
	local best, bestScore
	for _, candidate in ipairs(list) do
		local dx, dy = candidate.x - fromX, candidate.y - fromY
		local forward = dx * direction[1] + dy * direction[2]
		if forward > 6 then
			local side = math.abs(dx * direction[2]) + math.abs(dy * direction[1])
			local score = forward + side * 2.5
			if not bestScore or score < bestScore then
				best, bestScore = candidate, score
			end
		end
	end
	return best
end

function G.CursorSnap(name)
	local x, y = CursorPosition()
	local target = G.SnapChoose(Candidates(), x, y, name)
	if target then MoveTo(target) end
end

-- Top left button of whatever just opened.
function G.CursorFirst()
	local list = Candidates()
	local best, bestScore
	local RANK = { DIALOG = 3, FULLSCREEN_DIALOG = 4, HIGH = 2, MEDIUM = 1 }
	for _, candidate in ipairs(list) do
		local rank = RANK[candidate.strata] or 0
		local score = rank * 100000 + candidate.y - candidate.x
		if not bestScore or score > bestScore then
			best, bestScore = candidate, score
		end
	end
	if best then MoveTo(best) end
end

-- ---- which windows are open --------------------------------------------------------------------------------

local POPUPS = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }
-- Not need-or-greed rolls: those appear mid-fight, and Back gets the cursor for them.
local WINDOWS = {
	"LootFrame", "GameMenuFrame", "WorldMapFrame", "InterfaceOptionsFrame", "VideoOptionsFrame", "AudioOptionsFrame",
	"ChatConfigFrame", "HelpFrame", "BattlefieldFrame", "GuildRegistrarFrame", "PetitionFrame",
}
for i = 1, 13 do WINDOWS[#WINDOWS + 1] = "ContainerFrame" .. i end

local function AnyShown(list)
	for i = 1, #list do
		local frame = _G[list[i]]
		if frame and frame:IsShown() then return true end
	end
	return false
end

function G.WindowOpen()
	if GetUIPanel("left") or GetUIPanel("center") or GetUIPanel("right") or GetUIPanel("doublewide")
		or GetUIPanel("fullscreen") then
		return true
	end
	return AnyShown(WINDOWS) or AnyShown(POPUPS)
end

local entered = false       -- this mode was entered because a window opened, so closing it ends the mode
local manual = false        -- the player asked for the cursor with Back; only Back or East ends that
local dismissed = false     -- Back with a window still open: leave it alone until no window is open
local firstButtonIn         -- moving the cursor waits a beat: see "update" below
local checkIn = 0

function G.EnterCursor(fromPlayer)
	if fromPlayer then manual = true else entered = true end
	if G.mode == "aim" then SpellStopTargeting() end
	G.SetMode("cursor")
end

function G.LeaveCursor(dismiss)
	manual, entered = false, false
	firstButtonIn = nil
	dismissed = dismiss and G.WindowOpen() or false
	if G.mode == "cursor" then G.SetMode("world") end
end

-- Their Cancel buttons, the way Escape closes them, so unsaved changes are put back.
local CANCELLED = {
	VideoOptionsFrame = "VideoOptionsFrameCancel",
	AudioOptionsFrame = "AudioOptionsFrameCancel",
	InterfaceOptionsFrame = "InterfaceOptionsFrameCancel",
}

local function CloseWindowsAndPanels()
	if AnyShown(POPUPS) then
		-- Answers it the way Escape does. A popup that can't be escaped (release spirit) stays, as it should.
		if StaticPopup_EscapePressed() then return true end
	end
	for frameName, buttonName in pairs(CANCELLED) do
		local frame, button = _G[frameName], _G[buttonName]
		if frame and button and frame:IsShown() then
			N.Call(button.Click, button)
			return true
		end
	end
	local closed = false
	if LootFrame and LootFrame:IsShown() then
		CloseLoot()
		closed = true
	end
	for i = 1, 13 do
		local bag = _G["ContainerFrame" .. i]
		if bag and bag:IsShown() then closed = true end
	end
	if closed then CloseAllBags() end
	if CloseWindows() then closed = true end
	for i = 1, #WINDOWS do
		local frame = _G[WINDOWS[i]]
		if frame and frame:IsShown() then
			-- Never frame:Hide() on these: a panel hidden that way keeps its slot, and GetUIPanel says it's open for good.
			HideUIPanel(frame)
			closed = true
		end
	end
	return closed
end

local function CloseThings()
	if SpellIsTargeting() then
		SpellStopTargeting()
	elseif CursorHasItem() or CursorHasSpell() then
		ClearCursor()
	elseif not CloseWindowsAndPanels() then
		-- Nothing East can close. Hands the controls back rather than getting stuck in here.
		G.LeaveCursor(true)
	end
end

local scrollButton, scrollIn

local function Scroll(name)
	N.Wheel(name == "LT" and 1 or -1)
end

local clicked = {}
local CLICKS = { SOUTH = "left", WEST = "right" }

G.handlers.cursor = function(name, down)
	if CLICKS[name] then
		if not down and not clicked[name] then return false end
		clicked[name] = down or nil
		N.MouseButton(CLICKS[name], down)
	elseif name == "LT" or name == "RT" then
		if down then
			scrollButton, scrollIn = name, SCROLL_FIRST
			Scroll(name)
		elseif scrollButton == name then
			scrollButton = nil
		end
	elseif DIRECTIONS[name] then
		if down then G.CursorSnap(name) end
	elseif name == "EAST" then
		if down then CloseThings() end
	elseif name == "BACK" then
		if down then
			G.LeaveCursor(true)
		end
	elseif name == "START" or name == "LB" or name == "RB" or name == "L3" or name == "R3" then
		return false
	end
	return true
end

G.Listen("update", function(elapsed)
	if scrollButton and G.mode == "cursor" then
		scrollIn = scrollIn - elapsed
		if scrollIn <= 0 then
			scrollIn = SCROLL_REPEAT
			Scroll(scrollButton)
		end
	end

	-- Mouselook keeps the cursor's old position and puts it back when it ends, so the move has to come after that.
	if firstButtonIn and G.mode == "cursor" then
		firstButtonIn = firstButtonIn - elapsed
		if firstButtonIn <= 0 then
			firstButtonIn = nil
			G.CursorFirst()
		end
	end

	checkIn = checkIn - elapsed
	if checkIn > 0 then return end
	checkIn = 0.2

	local open = G.WindowOpen()
	if not open then
		dismissed = false
		if entered and not manual and G.mode == "cursor" then
			G.LeaveCursor()
		end
		entered = false
	elseif G.settings.autocursor == 1 and G.mode == "world" and not G.RadialOpen() and not entered and not dismissed
		and not InCombatLockdown() then
		G.EnterCursor(false)
		firstButtonIn = 0.05
	end
end)

G.Listen("mode", function(mode)
	if mode ~= "cursor" then
		-- A held click mustn't outlive the mode.
		for name, button in pairs(CLICKS) do
			if clicked[name] then
				clicked[name] = nil
				N.MouseButton(button, false)
			end
		end
		scrollButton = nil
	end
end)
