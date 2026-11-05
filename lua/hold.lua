-- Hold to keep casting, as WoW Forever does it: hold an ability's controller button or key, and the ability is used
-- again each time it's ready, until you let go. Off until /controller hold 1.
--
-- Keys need care. This client casts a bar key when it's let go, not when it's pressed: the key binding marks the
-- button "PUSHED" and the release clicks it if it still is (ActionButtonUp in FrameXML). A quick tap is left to the
-- client. Once a key has been held long enough to count as holding, the casting is ours, and the button is kept
-- "NORMAL" so letting go doesn't cast once more.
local N, G = ...

local HOLD_AFTER = 0.25 -- seconds down before a press counts as holding
local GAP = 0.2         -- between our tries, so a spell that is never "not ready" can't be spammed
local BACKOFF = 1       -- after a try the game answered with an error: out of range, can't see the target, moving
local UNCONFIRMED = 1   -- a try that showed no cooldown, cast or "on" waits this long before the next

local UseAction = G.Protect("UseAction")

-- The button a bar key's binding clicks right now, from ActionButtonUp and MultiActionButtonUp.
local function MainBarButton(index)
	if VehicleMenuBar and VehicleMenuBar:IsShown() and index <= VEHICLE_MAX_ACTIONBUTTONS then
		return _G["VehicleMenuBarActionButton" .. index]
	elseif BonusActionBarFrame and BonusActionBarFrame:IsShown() then
		return _G["BonusActionButton" .. index]
	end
	return _G["ActionButton" .. index]
end

local COMMANDS = {}
local MULTI_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }
for i = 1, 12 do
	COMMANDS["ACTIONBUTTON" .. i] = function() return MainBarButton(i) end
	for bar, name in ipairs(MULTI_BARS) do
		COMMANDS["MULTIACTIONBAR" .. bar .. "BUTTON" .. i] = function() return _G[name .. "Button" .. i] end
	end
end

-- Whether the ability in a slot should be used again now. Never one that toggles: auto attack, Auto Shot, a wand, a
-- mount or companion, or anything the bar shows as already on (a stance, an aura), which a second use would turn off.
local function Busy(slot)
	if IsCurrentAction(slot) then return true end
	local start, duration = GetActionCooldown(slot)
	if start and start > 0 and duration and duration > 0 and start + duration > GetTime() then return true end
	return UnitCastingInfo("player") or UnitChannelInfo("player")
end

function G.CanRepeat(slot)
	if not slot or not HasAction(slot) then return false end
	if IsAttackAction(slot) or IsAutoRepeatAction(slot) or IsCurrentAction(slot) then return false end
	if GetActionInfo(slot) == "companion" then return false end
	if not IsUsableAction(slot) then return false end
	local start, duration, enabled = GetActionCooldown(slot)
	if enabled == 0 then return false end
	if start and start > 0 and duration and duration > 0 and start + duration > GetTime() then return false end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
	if SpellIsTargeting() then return false end
	return true
end

-- What's being held, by "pad:EAST" or "key:SHIFT-3" (the modifiers held, which may be more than the binding's). Each: since, nextTry, lastTry, taken, and functions still(),
-- slot(), use(slot), and button() for keys.
local holds = {}

local function Clear()
	for id in pairs(holds) do holds[id] = nil end
end

-- The controller uses an ability on the press itself (world.lua), so holding only adds the repeats. The layer is the
-- one it was pressed on: letting go of a trigger mid-hold doesn't swap the ability.
function G.HoldPress(name, layer)
	if G.settings.hold ~= 1 then return end
	local now = GetTime()
	holds["pad:" .. name] = {
		since = now,
		nextTry = now,
		lastTry = now, -- the press was a try
		taken = true,
		still = function() return G.held[name] and G.mode == "world" end,
		slot = function() return G.ActionFor(name, layer) end,
		use = G.UseSlot,
	}
end

-- ---- keys -------------------------------------------------------------------------------------------------------

local byKey, baseKeys
local bindingsChanged = true

local function BaseOf(key)
	local base = key
	while true do
		local rest = string.match(base, "^ALT%-(.+)$") or string.match(base, "^CTRL%-(.+)$")
			or string.match(base, "^SHIFT%-(.+)$")
		if not rest then return base end
		base = rest
	end
end

local function ReadBindings()
	byKey, baseKeys = {}, {}
	local seen = {}
	for command in pairs(COMMANDS) do
		local keys = { GetBindingKey(command) }
		for _, key in ipairs(keys) do
			byKey[key] = command
			local base = BaseOf(key)
			if not seen[base] then
				seen[base] = true
				baseKeys[#baseKeys + 1] = base
			end
		end
	end
end

local function Modifiers()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "")
end

-- An addon's own bars (Bartender4, Dominos) take a bar key over with an override binding to their own button, whose slot
-- can differ from the Blizzard button's. Those keys are left alone. DragonUI's key-down casting is the exception: its
-- proxy clicks the same Blizzard button. A client that doesn't know the override argument reads the plain binding,
-- which matches.
local DRAGONUI_PROXY = "CLICK DragonUI_KeyPressButton_"

local function Overridden(key, command)
	local action = GetBindingAction(key, true)
	if action == nil or action == "" or action == command then return false end
	return string.sub(action, 1, #DRAGONUI_PROXY) ~= DRAGONUI_PROXY
end

-- The bar command a held key runs. Like the client: with modifiers held and nothing bound to that combination, the
-- plain key's binding runs, which is how [mod:shift] macros on a plain key work.
local function CommandFor(base, modifiers)
	local key = modifiers .. base
	local command = byKey[key]
	if not command and modifiers ~= "" then
		local other = GetBindingAction(key)
		if other == nil or other == "" then
			key, command = base, byKey[base]
		end
	end
	if command and not Overridden(key, command) then return command end
end

local function SlotOfButton(button)
	if not button then return nil end
	local slot = button.action
	if type(slot) ~= "number" then slot = button:GetAttribute("action") end
	return type(slot) == "number" and slot or nil
end

local function TypingOrBinding()
	if GetCurrentKeyBoardFocus() then return true end
	return KeyBindingFrame and KeyBindingFrame:IsShown()
end

-- As the bar button's own click would: Alt (the self cast modifier) casts on yourself, the focus cast one on the focus.
local function UseFromKey(slot)
	local unit
	if IsModifiedClick("SELFCAST") then
		unit = "player"
	elseif IsModifiedClick("FOCUSCAST") then
		unit = "focus"
	end
	UseAction(slot, unit, "LeftButton")
end

local function ScanKeys(now)
	if bindingsChanged then
		bindingsChanged = false
		ReadBindings()
	end
	local modifiers = Modifiers()
	local typing = TypingOrBinding()
	for i = 1, #baseKeys do
		local base = baseKeys[i]
		if not typing and N.KeyHeld(base) then
			local command = CommandFor(base, modifiers)
			local id = "key:" .. modifiers .. base
			if command and not holds[id] then
				local button = COMMANDS[command]
				holds[id] = {
					since = now,
					nextTry = now,
					taken = false,
					-- Same key, same modifiers: shift let go mid-hold can be a different binding, so this hold ends.
					-- So does opening chat.
					still = function()
						return N.KeyHeld(base) and Modifiers() == modifiers and not TypingOrBinding()
					end,
					button = button,
					slot = function() return SlotOfButton(button()) end,
					use = UseFromKey,
				}
			end
		end
	end
end

-- ---- every frame ------------------------------------------------------------------------------------------------

-- Event scripts only leave a note: any addon can find and call them.
local errorAt = 0
local events = CreateFrame("Frame")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_BINDINGS" then
		bindingsChanged = true
	else
		errorAt = GetTime()
	end
end)

-- The method from a button of our own: one read off a bar button could be an addon's function, and Call would run it
-- clean.
local SetButtonState = CreateFrame("Button").SetButtonState
local function KeepNormal(button)
	if not button then return end
	if button:GetButtonState() == "PUSHED" then
		N.Call(SetButtonState, button, "NORMAL")
	end
end

local function Step(h, now)
	if h.taken and h.button then KeepNormal(h.button()) end
	-- Any error since the last try, however long the server took to answer.
	if h.lastTry and errorAt >= h.lastTry then
		h.nextTry = math.max(h.nextTry, errorAt + BACKOFF)
	end
	if now - h.since < HOLD_AFTER or now < h.nextTry then return end
	local slot = h.slot()
	-- A try that never showed a cooldown, a cast or "on" may have been a toggle whose state is still on its way from
	-- the server: give it time before trying again.
	if h.lastTry and not h.confirmed then
		if slot and Busy(slot) then
			h.confirmed = true
		elseif now < h.lastTry + UNCONFIRMED then
			return
		end
	end
	if not G.CanRepeat(slot) then return end
	h.taken = true
	if h.button then KeepNormal(h.button()) end
	h.lastTry, h.nextTry, h.confirmed = now, now + GAP, false
	h.use(slot)
	if Busy(slot) then h.confirmed = true end
end

G.Listen("tick", function(elapsed, inFront)
	if G.settings.hold ~= 1 or not inFront or not N.InWorld() then
		Clear()
		return
	end
	local now = GetTime()
	ScanKeys(now)
	for id, h in pairs(holds) do
		if not h.still() then
			holds[id] = nil
		else
			G.Safe("hold", Step, h, now)
		end
	end
end)

-- The controller let go of everything (unplugged, rested, switched off). Keys are still held, or not, as they were.
G.Listen("release", function()
	for id in pairs(holds) do
		if string.sub(id, 1, 4) == "pad:" then holds[id] = nil end
	end
end)

N.Log("hold loaded")
