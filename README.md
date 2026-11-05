# Controller support for the 3.3.5a client

Plug in a controller and play. No addon, no key mapper, nothing to set up. Modelled on what WoW Forever's built-in
controller mode does, rebuilt for 3.3.5a: Forever's own interface code depends on engine features this client doesn't
have, so its design and button art came across, not its code.

## Playing

| Button | In the world | With a window open |
| --- | --- | --- |
| Left stick | Move | Move |
| Right stick | Camera | Move the cursor |
| South (A, Cross) | Jump, or talk/loot/use what's nearby | Left click |
| East, West, North, D-pad | Abilities | East closes, West right-clicks, D-pad jumps between buttons |
| Hold LT, RT, or both | Other abilities on those same buttons | LT and RT scroll |
| RB | Tap: next enemy. Hold: pick from a ring | Same |
| LB | Tap: next friend. Hold: pick from a ring, yourself at the top | Same |
| Start | Ring of the game's windows | Same |
| Back | Hand the controls to the cursor | Hand them back, leaving the window open |
| Left stick click | Auto-run | Auto-run |
| Right stick click | Sit, or descend when flying or swimming | Same |

Buttons follow your action bars. In the order they fill: the base layer takes the first 7 slots of the main bar (it
follows stance and page changes as the bar does, and vehicles), then LT, RT and both triggers take the rest of the main
bar, bottom left bar and bottom right bar: 31 abilities.

Spells placed on the ground (Blizzard, Flamestrike) show the reticle: aim with the right stick, South places it, East
cancels. Windows that open take the cursor to their first button, except in combat, where they wait for you to press Back
so your abilities stay yours. Need-or-greed rolls always wait for Back. A harmful spell with no enemy targeted picks the
nearest one first.

`/controller` in chat lists the settings: `on`, `off`, `camera`, `cursor`, `invert`, `hud`, `autotarget`, `autocursor`,
`rumble`. They save to `WTF\Controller.txt`.

Keyboard and mouse keep working alongside it. Without a controller nothing shows and nothing changes.

## Controllers

Everything goes through [SDL3](https://libsdl.org): Xbox, PlayStation, Switch and Steam controllers, and generic pads SDL
has a mapping for. The on-screen buttons follow the controller: letters for Xbox, shapes for PlayStation, Nintendo's own
layout, numbers for anything else. A pad SDL doesn't know can get a mapping from a `gamecontrollerdb.txt` next to the DLL.

## Requirements

- The Windows 3.3.5a client, build 12340, with an unedited code section where the frame handler is registered. Another
  build is detected and left alone.
- Windows 7 or later. Nothing else to install: no runtime, no driver beyond the controller's own.

## Installing

Download the zip from [Releases](../../releases) and put `msacm32.dll` and `SDL3.dll` next to `Wow.exe`. To remove it, delete both. It works alongside DLLs that load the same
way under other names (LuxVelum's `version.dll`, AwesomeWotlk's `dinput8.dll`).

`Logs\Controller.log` says what it found. The button art unpacks itself to `Interface\GamePad` on first start.

## How it works

- **Loading.** `Wow.exe` imports `msacm32.dll`, and Windows looks next to the exe first. `src/proxy.c` forwards all its
  exports to the real one in the system folder. `Wow.exe` itself isn't edited on disk.
- **Each frame.** The UI registers its per-frame handler with a `push 0x495810`. The DLL changes that one number in
  memory, before the code runs, to a function that ticks and then calls the original. If those bytes aren't what's
  expected (another build), it changes nothing and the game runs as if the DLL weren't there.
- **Input.** A player with no controller never starts SDL: Windows is asked every couple of seconds whether anything
  controller-like is plugged in. `SDL3.dll` is loaded at run time, so a missing copy only turns controllers off.
- **The UI.** `lua/*.lua` is built into the DLL. The DLL compiles and runs each file itself with no taint, so it's the
  client's code, not an addon. That's what lets it move, cast and target, in combat too.
- **Out of addons' reach.** The files get the native functions and a shared table as arguments, so there are no globals
  for an addon to find, and the frame function sits in the Lua registry rather than on a frame, where `EnumerateFrames`
  and `GetScript` would hand it out. The `/controller` command is the one thing visible, and all it can do is pass text.
- **Taint.** Reading anything an addon has touched taints running code. So each frame starts clean, and each protected
  call runs clean with its arguments cleaned (`l_call` in `src/main.c`). That only works during the frame function, so
  nothing can use it from anywhere else. A slash command, which can arrive through addon-tainted chat code, passes as text
  through the DLL rather than writing to the UI's tables.
- **Camera and clicks** are real mouse events (`SendInput`), sent only while the game is the window in front. The DLL
  remembers any button it holds down and always lets go: on losing focus, on a UI reload, on exit.
- **No C runtime.** `Wow.exe` imports this DLL directly, so a dependency Windows can't find would stop the game starting.
  It imports `kernel32` and `user32` only, and the build fails otherwise.

## Differences from Forever

- Area spells can be placed by hand; Forever's alpha places them on the target.
- The ally ring opens with yourself straight up, since players of Forever report self-targeting in a hurry being hard.
- Menus use the real mouse cursor with a D-pad jump between buttons, so addon windows work with nothing added to them.
- The enemy ring lists enemies from nameplates, the only such list in the client's Lua. With nameplates off, holding RB
  steps backward through targets instead.
- No analog walking: the client's movement is on or off.

## Building

```bash
ZIG=/path/to/zig ./build.sh
```

Needs [Zig](https://ziglang.org) (tested with 0.17.1), `luac`, Python 3. No Windows machine needed.

## Tests

```bash
clang -Isrc tests/test_logic.c src/logic.c -o /tmp/test_logic && /tmp/test_logic
```

```bash
luajit tests/test_ui.lua
```

```bash
python3 tools/check_api.py <Wow.exe> <folder of extracted FrameXML and GlueXML files>
```

`test_ui.lua` drives the real Lua files with a pretend client and controller. `check_api.py` proves every game function
the Lua uses exists in the client. Neither can show that the game agrees.

`tools/make_atlas.py` and `tools/make_art.py` rebuild `lua/atlas.lua` and `art/*.blp`. `tools/preview_atlas.py` draws every
button picture into a PNG, to check them by eye.

## Status

Played on a Windows 3.3.5a client on 2026-11-05 and works. `TEST-STEPS.md` is the checklist to repeat after a change.

## Credits and licences

- This project's own code is MIT, see `LICENSE`.
- [SDL3](https://libsdl.org), zlib licence, `third_party/SDL3-LICENSE.txt`. `third_party/SDL3.dll` is the official
  3.4.20 build, unchanged.
- Client addresses were read from the disassembly of the stock exe. `FrostAtom/awesome_wotlk` (GPL-3.0) was the map for
  where to look, and no code was taken from it.
- Button art in `art/` is from WoW Forever's client files, Blizzard Entertainment's, not covered by any licence here.
- Design follows WoW Forever's controller mode as players describe it and as its public interface files show.
