-- The ring picker: hold a shoulder button to choose a target, or tap Start for the game's windows. The right stick
-- points at an item. Letting go of the shoulder (or pressing South) picks it.
local N, G = ...

local RADIUS = 130
local SLOTS = 10
local DEADZONE = 0.45
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ring = CreateFrame("Frame", nil, UIParent)
ring:SetFrameStrata("FULLSCREEN_DIALOG")
ring:SetSize(RADIUS * 2 + 120, RADIUS * 2 + 120)
ring:SetPoint("CENTER", 0, 40)
ring:Hide()

local title = ring:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("CENTER")

local function NewSlot()
	local slot = CreateFrame("Frame", nil, ring)
	slot:SetSize(96, 58)
	slot.back = slot:CreateTexture(nil, "BACKGROUND")
	slot.back:SetAllPoints()
	slot.back:SetTexture(WHITE)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetSize(28, 28)
	slot.icon:SetPoint("TOP", 0, -4)
	slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	slot.label:SetPoint("BOTTOM", 0, 13)
	slot.label:SetWidth(92)
	slot.label:SetHeight(12)
	slot.health = CreateFrame("StatusBar", nil, slot)
	slot.health:SetStatusBarTexture(WHITE)
	slot.health:SetStatusBarColor(0.2, 0.8, 0.3)
	slot.health:SetPoint("BOTTOMLEFT", 4, 4)
	slot.health:SetPoint("BOTTOMRIGHT", -4, 4)
	slot.health:SetHeight(6)
	slot.health:SetMinMaxValues(0, 1)
	return slot
end

local slots = {}
local items, chosen, releaseButton

local function Paint()
	for i, slot in ipairs(slots) do
		if i == chosen then
			slot.back:SetVertexColor(0.95, 0.75, 0.2, 0.9)
		else
			slot.back:SetVertexColor(0, 0, 0, 0.72)
		end
	end
end

local function Close()
	if items then
		items, chosen, releaseButton = nil, nil, nil
		ring:Hide()
		G.Fire("radialClosed")
	end
end

function G.RadialOpen()
	return items ~= nil
end

function G.OpenRadial(title_text, list, release)
	if #list == 0 then return false end
	items, chosen, releaseButton = list, nil, release
	title:SetText(title_text)
	for i = 1, math.max(#slots, #list, 1) do
		if i <= #list and i <= SLOTS then
			local slot = slots[i]
			if not slot then
				slot = NewSlot()
				slots[i] = slot
			end
			local item = list[i]
			-- First item straight up, then clockwise.
			local angle = math.pi / 2 - (i - 1) * (2 * math.pi / math.min(#list, SLOTS))
			slot:ClearAllPoints()
			slot:SetPoint("CENTER", ring, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
			slot.label:SetText(item.label)
			slot.icon:SetTexture(item.icon)
			if item.icon then slot.icon:Show() else slot.icon:Hide() end
			if item.health then
				slot.health:SetValue(item.health)
				slot.health:Show()
			else
				slot.health:Hide()
			end
			slot:Show()
		elseif slots[i] then
			slots[i]:Hide()
		end
	end
	Paint()
	ring:Show()
	G.Fire("radialOpened")
	return true
end

local function Pick()
	local item = chosen and items and items[chosen]
	Close()
	if item and item.action then
		G.Safe("radial pick", item.action)
	end
end

G.Listen("update", function()
	if not items then return end
	local x, y = G.rx, G.ry
	if x * x + y * y < DEADZONE * DEADZONE then return end
	local count = math.min(#items, SLOTS)
	-- Clockwise from straight up.
	local angle = math.atan2(x, y)
	if angle < 0 then angle = angle + 2 * math.pi end
	local index = math.floor(angle / (2 * math.pi) * count + 0.5) % count + 1
	if index ~= chosen then
		chosen = index
		Paint()
	end
end)

G.Listen("release", Close)

G.handlers.radial = function(name, down)
	if not items then return false end
	if name == releaseButton and not down then
		-- Alt-tab lets go of everything too, and that isn't a choice.
		if G.inFront then Pick() else Close() end
		return true
	end
	-- Whatever was held when the ring opened still has to let go: a jump, a click.
	if not down then return false end
	if name == "SOUTH" then
		Pick()
	elseif name == "EAST" or name == "START" then
		Close()
	end
	-- Abilities wait while the ring is up. Movement isn't a button, so walking still works.
	return true
end
