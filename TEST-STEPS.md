# Test steps

Run these after any change. They go in order of what could go wrong first, and each step tells you what to send back if
it fails. The file that helps most is `Logs\Controller.log` in the game folder.

**The launcher deletes files it doesn't know about, these two included.** Close it first and start `Wow.exe` directly for
this test. Opening the launcher later removes them, which is also the uninstall.

## 1. Without a controller

1. Close the launcher and the game. Leave any controller unplugged.
2. Copy `msacm32.dll` and `SDL3.dll` next to `Wow.exe`.
3. Start `Wow.exe` directly. Log in and play for a minute.
4. Check: the game starts and plays as usual, nothing new on screen.
5. Check `Logs\Controller.log` has these lines:
   - `controller DLL loaded`
   - `frame handler installed`
   - `starting login UI`, then `login UI loaded`
   - `starting game UI`, then `core loaded, secure=1` and `world loaded`
   - **Not** `SDL ready`: with nothing plugged in, SDL should never start. If it does, something on your PC looks like a
     controller to Windows, which is fine, but tell me.

If the game won't start: delete the two DLLs and send me the error. If `secure=` says anything other than 1, or any line
starts `error:`, send me the log.

## 2. The controller is seen

1. Plug the controller in while the game runs. Within a few seconds the log should say `SDL ready`, then
   `controller added: <name> (art ltr)`. `art` should be `ltr` for Xbox, `shp` for PlayStation, `rev` for Nintendo.
2. Press any button. The cross of abilities should appear above your action bars, with that controller's own button
   pictures.

**Green or missing pictures** mean the client couldn't read the art. Tell me which.

## 3. Moving and camera

- Left stick: forward, back, strafe, diagonals. Let go: stops at once.
- Right stick: the camera turns, and the character follows while running. Is the speed good? `/controller camera 900`
  changes it.
- South: jump. Left stick click: auto-run. Right stick click: sit.
- Alt-tab away while running: the character must stop.

## 4. Abilities

- East, West, North and the D-pad use bar slots 1 to 7. Hold LT or RT, or both: the cross changes and the same buttons
  use other slots.
- **Do it in combat.** This is the main unknown. If it says "Interface action failed because of an AddOn" or nothing
  happens, send me the log and your list of addons.
- A stance change (druid form, rogue stealth, warrior stance): the first row should follow it.
- A ground spell if you have one: the right stick aims, South places, East cancels.
- `/controller style xiv`: the cross becomes three sets, LT's on the left, RT's on the right and the buttons' own in
  the middle. Hold LT, then RT, then both: the held set grows and the others fade, and nothing moves sideways. Does it
  fit on screen? `/controller style wow` puts the cross back.

## 5. Targeting

- Tap RB: next enemy. Tap LB: next friend.
- Hold LB: a ring with you at the top. Point with the right stick, let go. Try it in a party.
- Hold RB near enemies with nameplates on: a ring of their names.

## 6. Interact

- Stand by a corpse with loot, a vendor, a mailbox, an herb or ore node. "Loot", "Talk" or "Use" shows above the bars. South
  does it. **If the game crashes here, tell me what you were next to.** This step calls the most client code directly.

## 7. Windows

- Start: the ring of windows. Point, then South.
- With a window open: right stick moves the cursor, D-pad jumps between buttons, South clicks, West right-clicks, East
  closes, triggers scroll. Try a bag, a vendor, a quest, a loot window and something from an addon.
- Back gives you the cursor with nothing open. Back again returns. With a window open, Back returns your abilities and
  leaves the window up.
- In combat, windows shouldn't take over: open a bag mid-fight and your abilities should keep working.
- Die: East must not make the Release Spirit box disappear.
- Hold South in a window, alt-tab: Windows must not think the mouse button is still held.
- Need-or-greed rolls: Back, then click.

## 8. Character select

Go back to character select: D-pad up and down picks, South enters the world.

## 9. Other controllers

If you have more types, unplug one and plug in another. The button pictures should change. A pad I couldn't test may have
the wrong buttons, so tell me its name from the log.

## 10. Hold to keep casting

1. Esc, Interface, Game tab, Combat: **Press and Hold Casting** sits under the self cast key, unticked. Tick it and press
   Okay. Open it again: still ticked. Untick and press Cancel: still ticked. `/controller hold 0` in chat, then open the
   panel: unticked. Tick it again for the steps below. If the box overlaps something or is missing, send a screenshot.
2. **Keyboard**, controller unplugged: put a spell with a short cooldown on bar key 1 (main bar) and one on a bottom left
   bar key. Tap each: one cast, as before. Hold each on a target dummy or a mob: it casts, then casts again each time the
   cooldown or global cooldown ends. Let go: no extra cast and no "Spell is not ready yet".
3. Shift: a macro with `[mod:shift]` on a plain key, held with Shift down: the Shift spell repeats. A heal held with Alt:
   it lands on you, not the target. Try once with DragonUI's key-down casting on as well.
4. Hold the Attack ability, Auto Shot or a wand, a mount, and an aura or stance already on: none of them should turn off.
5. Hold a key while typing in chat: nothing casts. Hold one out of range: an error about once a second, not a stream.
6. **Controller**: hold East on a mob. It casts on the press and again each time it's ready. Hold LT, press East, let go
   of LT while still holding East: it keeps using the LT ability.
7. In combat, all of the above: if "Interface action failed because of an AddOn" shows, send me the log.
8. Untick the box: holding goes back to one cast.

## Removing it

Delete `msacm32.dll`, `SDL3.dll`, `WTF\Controller.txt` and `Interface\GamePad`, or just open the launcher, which removes the
two DLLs.
