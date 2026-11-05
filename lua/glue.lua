-- Character select: choose with the D-pad, South enters the world. Typing a password still takes a keyboard.
local N = ...

local REPEAT_FIRST, REPEAT_NEXT = 0.4, 0.15
local held, repeatIn

local function Step(amount)
	local count = GetNumCharacters()
	if count == 0 or not CharacterSelect or not CharacterSelect:IsShown() then return end
	local index = (CharacterSelect.selectedIndex or 1) + amount
	if index < 1 then index = count elseif index > count then index = 1 end
	CharacterSelect_SelectCharacter(index)
end

local function Press(name)
	if not CharacterSelect or not CharacterSelect:IsShown() then return end
	if name == "UP" then
		Step(-1)
	elseif name == "DOWN" then
		Step(1)
	elseif name == "SOUTH" or name == "START" then
		if GetNumCharacters() > 0 then CharacterSelect_EnterWorld() end
	end
end

N.SetDriver(function(elapsed)
	while true do
		local name, down = N.NextEvent()
		if not name then break end
		if down then
			held, repeatIn = name, REPEAT_FIRST
			N.Try(Press, name)
		elseif held == name then
			held = nil
		end
	end
	if held == "UP" or held == "DOWN" then
		repeatIn = repeatIn - elapsed
		if repeatIn <= 0 then
			repeatIn = REPEAT_NEXT
			N.Try(Press, held)
		end
	end
end)

N.Log("login UI loaded")
