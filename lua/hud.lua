-- The on-screen cross of abilities: what each button does right now on the layer being held, with the controller's
-- own button pictures. Only there while a controller is in use.
local N, G = ...

local Atlas = G.Atlas
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BUTTON_SIZE = 40
local SPACING = 44
local CLUSTER_GAP = 170

local hud = CreateFrame("Frame", nil, UIParent)
hud:SetSize(CLUSTER_GAP * 2 + SPACING * 2, SPACING * 3)
hud:SetPoint("BOTTOM", 0, 150)
hud:SetFrameStrata("MEDIUM")
hud:Hide()

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

-- Offsets of each position from its cluster's middle.
local LAYOUT = {
	NORTH = { 1, 0, 1 }, EAST = { 1, 1, 0 }, SOUTH = { 1, 0, -1 }, WEST = { 1, -1, 0 },
	UP = { -1, 0, 1 }, RIGHT = { -1, 1, 0 }, DOWN = { -1, 0, -1 }, LEFT = { -1, -1, 0 },
}

local buttons = {}

local function NewButton(position)
	local place = LAYOUT[position]
	local frame = CreateFrame("Frame", nil, hud)
	frame:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	frame:SetPoint("CENTER", place[1] * CLUSTER_GAP + place[2] * SPACING, place[3] * SPACING)
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
	frame.glyph:SetSize(18, 18)
	frame.glyph:SetPoint("BOTTOMRIGHT", 4, -4)
	frame.count = frame.glyphHolder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.count:SetPoint("TOPRIGHT", -2, -2)
	frame.position = position
	buttons[position] = frame
	return frame
end

for position in pairs(LAYOUT) do NewButton(position) end

-- The triggers, lit while held.
local function NewTrigger(name, x)
	local holder = CreateFrame("Frame", nil, hud)
	holder:SetSize(26, 26)
	holder:SetPoint("CENTER", x, 0)
	holder.glyph = holder:CreateTexture(nil, "OVERLAY")
	holder.glyph:SetAllPoints()
	holder.button = name
	return holder
end
local triggers = { NewTrigger("LT", -24), NewTrigger("RT", 24) }

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

local function SetAllGlyphs()
	for position, frame in pairs(buttons) do SetGlyph(frame.glyph, position) end
	for _, holder in ipairs(triggers) do SetGlyph(holder.glyph, holder.button) end
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

local lastLayer
local paintIn = 0

local function Paint()
	local layer = G.Layer()
	for _, frame in pairs(buttons) do PaintButton(frame, layer) end
	triggers[1]:SetAlpha(G.held.LT and 1 or 0.35)
	triggers[2]:SetAlpha(G.held.RT and 1 or 0.35)
	lastLayer = layer
end

local function Refresh()
	if G.active and G.settings.hud == 1 and G.mode == "world" then
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
