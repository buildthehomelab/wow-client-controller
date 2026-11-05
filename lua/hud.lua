-- The on-screen cross of abilities, with the controller's own button pictures. Only there while a controller is in
-- use. Two styles, picked with /controller style:
--   wow  WoW Forever's: one cross, the D-pad's four on the left and the face buttons' four on the right, showing what
--        the buttons do on the layer being held, with LT and RT between them lit while held.
--   xiv  A cross hotbar: LT's set on the left, RT's on the right and the buttons' own set in the middle, all at once.
--        The set being held is big and bright and the others small and faint, so what's on each trigger is always in
--        sight. Both triggers bring their set to the middle.
local N, G = ...

local Atlas = G.Atlas
local WHITE = "Interface\\Buttons\\WHITE8X8"
local STYLES = { [0] = "wow", [1] = "xiv" }
G.STYLES = STYLES

-- wow
local BUTTON_SIZE = 40
local SPACING = BUTTON_SIZE * 1.1
local CLUSTER_GAP = 170

-- xiv: the held set and the others.
local BIG, SMALL = 40, 24
local GAP = 1.1          -- spacing as a share of the button size, both styles
local FAINT = 0.45
local SET_GAP = 30       -- between neighbouring sets

local hud = CreateFrame("Frame", nil, UIParent)
hud:SetSize(CLUSTER_GAP * 2 + SPACING * 2, SPACING * 3)
hud:SetPoint("BOTTOM", 0, 150)
hud:SetFrameStrata("MEDIUM")
hud:Hide()
G.hudFrame = hud

local function SetGlyph(texture, button)
	local set = Atlas[G.family] or Atlas.ltr
	local cell = set[button]
	if cell then
		texture:SetTexture("Interface\\GamePad\\" .. cell[1])
		texture:SetTexCoord(cell[2], cell[3], cell[4], cell[5])
		texture:Show()
	else
		texture:Hide()
	end
end
G.SetGlyph = SetGlyph

-- Where each position sits: which cluster (-1 the D-pad's, 1 the face buttons'), then across and up in that cluster.
local LAYOUT = {
	NORTH = { 1, 0, 1 }, EAST = { 1, 1, 0 }, SOUTH = { 1, 0, -1 }, WEST = { 1, -1, 0 },
	UP = { -1, 0, 1 }, RIGHT = { -1, 1, 0 }, DOWN = { -1, 0, -1 }, LEFT = { -1, -1, 0 },
}

local function NewButton(parent, position)
	local frame = CreateFrame("Frame", nil, parent)
	frame.back = frame:CreateTexture(nil, "BACKGROUND")
	frame.back:SetAllPoints()
	frame.back:SetTexture(WHITE)
	frame.back:SetVertexColor(0, 0, 0, 0.55)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", 2, -2)
	frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame.icon)
	frame.glyphHolder = CreateFrame("Frame", nil, frame)
	frame.glyphHolder:SetAllPoints()
	frame.glyphHolder:SetFrameLevel(frame.cooldown:GetFrameLevel() + 2)
	frame.glyph = frame.glyphHolder:CreateTexture(nil, "OVERLAY")
	frame.glyph:SetPoint("BOTTOMRIGHT", 4, -4)
	frame.count = frame.glyphHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.count:SetPoint("TOPRIGHT", -2, -2)
	frame.position = position
	return frame
end

-- Sizes and places a button: size, the gap between its cluster's middles, and the middle of its set.
local function PlaceButton(frame, size, clusterGap, x, y)
	local place = LAYOUT[frame.position]
	local spacing = size * GAP
	frame:SetSize(size, size)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", x + place[1] * clusterGap + place[2] * spacing, y + place[3] * spacing)
	local glyph = math.floor(size * 0.45 + 0.5)
	frame.glyph:SetSize(glyph, glyph)
end

local function NewTrigger(parent, name)
	local holder = CreateFrame("Frame", nil, parent)
	holder.glyph = holder:CreateTexture(nil, "OVERLAY")
	holder.glyph:SetAllPoints()
	holder.button = name
	return holder
end

-- ---- wow --------------------------------------------------------------------------------------------------------
local wow = CreateFrame("Frame", nil, hud)
wow:SetAllPoints()
local wowButtons = {}
for position in pairs(LAYOUT) do
	local frame = NewButton(wow, position)
	PlaceButton(frame, BUTTON_SIZE, CLUSTER_GAP, 0, 0)
	wowButtons[position] = frame
end
-- The triggers, lit while held.
local wowTriggers = {}
for index, name in ipairs { "LT", "RT" } do
	local holder = NewTrigger(wow, name)
	holder:SetSize(26, 26)
	holder:SetPoint("CENTER", index == 1 and -24 or 24, 0)
	wowTriggers[index] = holder
end

-- ---- xiv --------------------------------------------------------------------------------------------------------
-- Three sets: left is LT's, right is RT's, the middle is the buttons' own or, with both triggers held, both's.
local xiv = CreateFrame("Frame", nil, hud)
xiv:SetAllPoints()
local SET_KEYS = { "LT", "MIDDLE", "RT" }
local sets = {}
for _, key in ipairs(SET_KEYS) do
	local set = { key = key, buttons = {}, labels = {} }
	set.frame = CreateFrame("Frame", nil, xiv)
	set.frame:SetAllPoints()
	for position in pairs(LAYOUT) do
		set.buttons[position] = NewButton(set.frame, position)
	end
	for index, name in ipairs { "LT", "RT" } do
		set.labels[index] = NewTrigger(set.frame, name)
	end
	sets[key] = set
end

-- The layer a set shows right now.
local function SetLayer(set, held)
	if set.key == "MIDDLE" then return held == "BOTH" and "BOTH" or "BASE" end
	return set.key
end

-- A set is two diamonds of three cells side by side: its whole width, how far each diamond's middle is from the
-- set's, and the step between cells.
local function SetMetrics(size)
	local spacing = size * GAP
	local diamond = 2 * spacing + size
	local gap = size * 0.4
	return 2 * diamond + gap, (diamond + gap) / 2, spacing
end

local function LayoutXiv(held)
	-- Fixed middles, far enough apart for a big set next to a small one, so a set never moves when it grows.
	local apart = (SetMetrics(BIG) + SetMetrics(SMALL)) / 2 + SET_GAP
	local middles = { LT = -apart, MIDDLE = 0, RT = apart }
	for _, key in ipairs(SET_KEYS) do
		local set = sets[key]
		local layer = SetLayer(set, held)
		local big = layer == held
		local size = big and BIG or SMALL
		local _, clusterGap, spacing = SetMetrics(size)
		local x = middles[key]
		for _, frame in pairs(set.buttons) do
			PlaceButton(frame, size, clusterGap, x, 0)
		end
		set.frame:SetAlpha(big and 1 or FAINT)
		-- Which trigger reaches the set, under its middle: nothing for the buttons' own.
		local label = math.floor(size * 0.55 + 0.5)
		local below = -(spacing + size / 2 + label / 2 + 4)
		local wants = (layer == "LT" and { "LT" }) or (layer == "RT" and { "RT" }) or (layer == "BOTH" and { "LT", "RT" }) or {}
		for index, holder in ipairs(set.labels) do
			local name = wants[index]
			if name then
				holder.button = name
				holder:SetSize(label, label)
				holder:ClearAllPoints()
				local offset = #wants == 2 and (index == 1 and -label / 2 - 1 or label / 2 + 1) or 0
				holder:SetPoint("CENTER", x + offset, below)
				SetGlyph(holder.glyph, name)
				holder:Show()
			else
				holder:Hide()
			end
		end
		set.layer = layer
	end
end

-- ---- painting ---------------------------------------------------------------------------------------------------
-- "Press South to loot"
local prompt = CreateFrame("Frame", nil, UIParent)
prompt:SetSize(180, 30)
prompt:SetPoint("BOTTOM", 0, 280)
prompt:SetFrameStrata("MEDIUM")
prompt:Hide()
prompt.glyph = prompt:CreateTexture(nil, "OVERLAY")
prompt.glyph:SetSize(26, 26)
prompt.glyph:SetPoint("LEFT", 30, 0)
prompt.text = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
prompt.text:SetPoint("LEFT", prompt.glyph, "RIGHT", 6, 0)

local PROMPT_WORDS = { loot = "Loot", talk = "Talk", use = "Use" }

function G.ShowPrompt(kind)
	if kind and G.settings.hud == 1 then
		SetGlyph(prompt.glyph, "SOUTH")
		prompt.text:SetText(PROMPT_WORDS[kind] or kind)
		prompt:Show()
	else
		prompt:Hide()
	end
end

local function Style()
	return STYLES[G.settings.style] or "wow"
end
G.Style = Style

local function SetAllGlyphs()
	for position, frame in pairs(wowButtons) do SetGlyph(frame.glyph, position) end
	for _, holder in ipairs(wowTriggers) do SetGlyph(holder.glyph, holder.button) end
	for _, set in pairs(sets) do
		for position, frame in pairs(set.buttons) do SetGlyph(frame.glyph, position) end
		for _, holder in ipairs(set.labels) do SetGlyph(holder.glyph, holder.button) end
	end
end

local function PaintButton(frame, layer)
	local slot = G.ActionFor(frame.position, layer)
	if not slot then
		-- South on the base layer: jump.
		frame.icon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
		frame.icon:SetVertexColor(0.55, 0.55, 0.55)
		frame.cooldown:Hide()
		frame.count:SetText("")
		return
	end
	local texture = GetActionTexture(slot)
	if not texture then
		frame.icon:SetTexture(nil)
		frame.cooldown:Hide()
		frame.count:SetText("")
		return
	end
	frame.icon:SetTexture(texture)
	local usable, noMana = IsUsableAction(slot)
	if IsActionInRange(slot) == 0 then
		frame.icon:SetVertexColor(0.8, 0.2, 0.2)
	elseif usable then
		frame.icon:SetVertexColor(1, 1, 1)
	elseif noMana then
		frame.icon:SetVertexColor(0.3, 0.4, 0.9)
	else
		frame.icon:SetVertexColor(0.4, 0.4, 0.4)
	end
	local start, duration, enable = GetActionCooldown(slot)
	if start and duration and duration > 0 and enable == 1 then
		frame.cooldown:SetCooldown(start, duration)
		frame.cooldown:Show()
	else
		frame.cooldown:Hide()
	end
	local count = GetActionCount(slot)
	frame.count:SetText((IsConsumableAction(slot) or IsStackableAction(slot)) and count or "")
end

local lastLayer, laidOut
local paintIn = 0

local function Paint()
	local layer = G.Layer()
	if Style() == "xiv" then
		if layer ~= laidOut then
			laidOut = layer
			LayoutXiv(layer)
		end
		for _, set in pairs(sets) do
			for _, frame in pairs(set.buttons) do PaintButton(frame, set.layer) end
		end
	else
		for _, frame in pairs(wowButtons) do PaintButton(frame, layer) end
		wowTriggers[1]:SetAlpha(G.held.LT and 1 or 0.35)
		wowTriggers[2]:SetAlpha(G.held.RT and 1 or 0.35)
	end
	lastLayer = layer
end

local function Refresh()
	if G.active and G.settings.hud == 1 and not G.ownBars and G.mode == "world" then
		local style = Style()
		if style == "xiv" then
			wow:Hide()
			xiv:Show()
		else
			xiv:Hide()
			wow:Show()
		end
		laidOut = nil
		hud:Show()
		Paint()
	else
		hud:Hide()
	end
end

G.Listen("update", function(elapsed)
	if not hud:IsShown() then return end
	paintIn = paintIn - elapsed
	-- The layer changes at once; icons and cooldowns can be a little behind.
	if G.Layer() ~= lastLayer or paintIn <= 0 then
		paintIn = 0.1
		Paint()
	end
end)

G.Listen("active", Refresh)
G.Listen("mode", Refresh)
G.Listen("settings", Refresh)
G.Listen("family", function()
	SetAllGlyphs()
	Refresh()
end)

SetAllGlyphs()

-- For tests/test_ui.lua.
G.hudParts = { wow = wow, xiv = xiv, sets = sets, wowButtons = wowButtons }
