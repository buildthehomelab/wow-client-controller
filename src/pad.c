#include "pad.h"
#include "log.h"

#include <windows.h>

#include <SDL3/SDL_gamepad.h>
#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_init.h>

#define MAX_PADS 8
#define REFRESH_TICKS 60
#define DEADZONE 0.18f

/* SDL functions, resolved by name. */
#define SDL_FUNCTIONS(X) \
    X(bool, SDL_SetHint, (const char *, const char *)) \
    X(bool, SDL_Init, (SDL_InitFlags)) \
    X(const char *, SDL_GetError, (void)) \
    X(void, SDL_free, (void *)) \
    X(int, SDL_AddGamepadMappingsFromFile, (const char *)) \
    X(void, SDL_SetGamepadEventsEnabled, (bool)) \
    X(void, SDL_SetJoystickEventsEnabled, (bool)) \
    X(SDL_JoystickID *, SDL_GetGamepads, (int *)) \
    X(SDL_Gamepad *, SDL_OpenGamepad, (SDL_JoystickID)) \
    X(void, SDL_CloseGamepad, (SDL_Gamepad *)) \
    X(bool, SDL_GamepadConnected, (SDL_Gamepad *)) \
    X(SDL_JoystickID, SDL_GetGamepadID, (SDL_Gamepad *)) \
    X(void, SDL_UpdateGamepads, (void)) \
    X(bool, SDL_GetGamepadButton, (SDL_Gamepad *, SDL_GamepadButton)) \
    X(Sint16, SDL_GetGamepadAxis, (SDL_Gamepad *, SDL_GamepadAxis)) \
    X(SDL_GamepadButtonLabel, SDL_GetGamepadButtonLabel, (SDL_Gamepad *, SDL_GamepadButton)) \
    X(const char *, SDL_GetGamepadName, (SDL_Gamepad *)) \
    X(bool, SDL_RumbleGamepad, (SDL_Gamepad *, Uint16, Uint16, Uint32))

#define X(ret, name, args) static ret (SDLCALL *p_##name) args;
SDL_FUNCTIONS(X)
#undef X

static SDL_Gamepad *g_pads[MAX_PADS];
static int g_active = -1;
static int g_ready;
static unsigned g_refresh;
static char g_held[BTN_COUNT];
static struct PadState g_state = { 0, "ltr", "", 0, 0, 0, 0, 0, 0 };

static const SDL_GamepadButton BUTTON_MAP[BTN_LT] = {
    SDL_GAMEPAD_BUTTON_SOUTH, SDL_GAMEPAD_BUTTON_EAST, SDL_GAMEPAD_BUTTON_WEST, SDL_GAMEPAD_BUTTON_NORTH,
    SDL_GAMEPAD_BUTTON_BACK, SDL_GAMEPAD_BUTTON_GUIDE, SDL_GAMEPAD_BUTTON_START,
    SDL_GAMEPAD_BUTTON_LEFT_STICK, SDL_GAMEPAD_BUTTON_RIGHT_STICK,
    SDL_GAMEPAD_BUTTON_LEFT_SHOULDER, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,
    SDL_GAMEPAD_BUTTON_DPAD_UP, SDL_GAMEPAD_BUTTON_DPAD_DOWN,
    SDL_GAMEPAD_BUTTON_DPAD_LEFT, SDL_GAMEPAD_BUTTON_DPAD_RIGHT,
};

/* Steam Input can present a pad through XInput alone, with no device behind it for the list below to show. Asking
   XInput about an empty slot is slow, so this runs far less often than the device list. */
#define XINPUT_EVERY 5

static int xinput_pad_present(void)
{
    static const char *const NAMES[] = { "xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll" };
    static DWORD (WINAPI *get_capabilities)(DWORD, DWORD, void *);
    static int looked;
    char capabilities[64];
    DWORD slot;

    if (!looked) {
        size_t i;
        looked = 1;
        for (i = 0; i < sizeof(NAMES) / sizeof(NAMES[0]) && !get_capabilities; i++) {
            HMODULE module = LoadLibraryA(NAMES[i]);
            if (module)
                get_capabilities = (DWORD (WINAPI *)(DWORD, DWORD, void *))(void *)GetProcAddress(module, "XInputGetCapabilities");
        }
    }
    if (!get_capabilities)
        return 0;
    for (slot = 0; slot < 4; slot++)
        if (get_capabilities(slot, 0, capabilities) == ERROR_SUCCESS)
            return 1;
    return 0;
}

/* SDL takes its time starting and has been known to stall on odd USB devices, so a player with no controller never
   starts it. If Windows won't say, assume there is one. */
int pad_device_present(void)
{
    static int xinput_wait;
    RAWINPUTDEVICELIST devices[64];
    UINT count = 64, found, i;

    found = GetRawInputDeviceList(devices, &count, sizeof(RAWINPUTDEVICELIST));
    if (found == (UINT)-1)
        return 1;
    for (i = 0; i < found; i++) {
        RID_DEVICE_INFO info;
        UINT size = sizeof(info);
        if (devices[i].dwType != RIM_TYPEHID)
            continue;
        info.cbSize = sizeof(info);
        if (GetRawInputDeviceInfoA(devices[i].hDevice, RIDI_DEVICEINFO, &info, &size) == (UINT)-1)
            return 1;
        /* Generic Desktop page: joystick, gamepad, multi-axis controller */
        if (info.hid.usUsagePage == 1 && (info.hid.usUsage == 4 || info.hid.usUsage == 5 || info.hid.usUsage == 8))
            return 1;
    }
    if (--xinput_wait <= 0) {
        xinput_wait = XINPUT_EVERY;
        return xinput_pad_present();
    }
    return 0;
}

int pad_init(const char *directory)
{
    char path[MAX_PATH + 32];
    HMODULE sdl;

    wsprintfA(path, "%s\\SDL3.dll", directory);
    sdl = LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!sdl) {
        log_line("SDL3.dll not loaded (error %lu); controllers are off", GetLastError());
        return 0;
    }
#define X(ret, name, args)                                                 \
    p_##name = (ret (SDLCALL *) args)(void *)GetProcAddress(sdl, #name);   \
    if (!p_##name) {                                                       \
        log_line("SDL3.dll has no %s; controllers are off", #name);        \
        return 0;                                                          \
    }
    SDL_FUNCTIONS(X)
#undef X

    /* The game has focus logic of its own, and pad_update drops input while it isn't in front. */
    p_SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    /* Raw input is read on SDL's own thread, away from the game's message loop. */
    p_SDL_SetHint(SDL_HINT_JOYSTICK_THREAD, "1");

    if (!p_SDL_Init(SDL_INIT_GAMEPAD)) {
        log_line("SDL_Init failed: %s", p_SDL_GetError());
        return 0;
    }
    /* We read state each tick; nothing would ever empty SDL's event queue. */
    p_SDL_SetGamepadEventsEnabled(false);
    p_SDL_SetJoystickEventsEnabled(false);

    wsprintfA(path, "%s\\gamecontrollerdb.txt", directory);
    if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) {
        int added = p_SDL_AddGamepadMappingsFromFile(path);
        log_line("gamecontrollerdb.txt: %d mappings", added);
    }
    g_ready = 1;
    g_refresh = REFRESH_TICKS;
    log_line("SDL ready");
    return 1;
}

static const char *family_of(SDL_Gamepad *pad)
{
    switch (p_SDL_GetGamepadButtonLabel(pad, SDL_GAMEPAD_BUTTON_SOUTH)) {
    case SDL_GAMEPAD_BUTTON_LABEL_A: return "ltr";
    case SDL_GAMEPAD_BUTTON_LABEL_B: return "rev";
    case SDL_GAMEPAD_BUTTON_LABEL_CROSS: return "shp";
    default: return "gen";
    }
}

static void refresh_pads(void)
{
    int count = 0, i, j;
    SDL_JoystickID *ids;

    for (i = 0; i < MAX_PADS; i++) {
        if (g_pads[i] && !p_SDL_GamepadConnected(g_pads[i])) {
            log_line("controller removed: %s", p_SDL_GetGamepadName(g_pads[i]));
            p_SDL_CloseGamepad(g_pads[i]);
            g_pads[i] = NULL;
            if (g_active == i)
                g_active = -1;
        }
    }
    ids = p_SDL_GetGamepads(&count);
    if (!ids)
        return;
    for (j = 0; j < count; j++) {
        int known = 0, slot = -1;
        for (i = 0; i < MAX_PADS; i++) {
            if (g_pads[i] && p_SDL_GetGamepadID(g_pads[i]) == ids[j])
                known = 1;
            else if (!g_pads[i] && slot < 0)
                slot = i;
        }
        if (!known && slot >= 0) {
            g_pads[slot] = p_SDL_OpenGamepad(ids[j]);
            if (g_pads[slot]) {
                const char *name = p_SDL_GetGamepadName(g_pads[slot]);
                log_line("controller added: %s (art %s)", name ? name : "?", family_of(g_pads[slot]));
                if (g_active < 0)
                    g_active = slot;
            }
        }
    }
    p_SDL_free(ids);
}

static float axis(SDL_Gamepad *pad, SDL_GamepadAxis which)
{
    return (float)p_SDL_GetGamepadAxis(pad, which) / 32767.0f;
}

/* The pad in use: the first other one with something pressed takes over. */
static void pick_active(void)
{
    int i, b;
    if (g_active >= 0 && g_pads[g_active]) {
        for (b = 0; b < BTN_LT; b++)
            if (p_SDL_GetGamepadButton(g_pads[g_active], BUTTON_MAP[b]))
                return;
    }
    for (i = 0; i < MAX_PADS; i++) {
        if (!g_pads[i] || i == g_active)
            continue;
        for (b = 0; b < BTN_LT; b++) {
            if (p_SDL_GetGamepadButton(g_pads[i], BUTTON_MAP[b])) {
                g_active = i;
                return;
            }
        }
    }
    if (g_active < 0) {
        for (i = 0; i < MAX_PADS; i++) {
            if (g_pads[i]) {
                g_active = i;
                return;
            }
        }
    }
}

static void set_button(struct EventQueue *queue, int button, int held)
{
    if (g_held[button] != (char)(held != 0)) {
        g_held[button] = (char)(held != 0);
        queue_push(queue, button, held);
    }
}

void pad_update(struct EventQueue *queue, int accept_input)
{
    SDL_Gamepad *pad;
    int b;

    if (!g_ready)
        return;
    p_SDL_UpdateGamepads();
    if (++g_refresh >= REFRESH_TICKS) {
        g_refresh = 0;
        refresh_pads();
    }
    pick_active();

    pad = (g_active >= 0) ? g_pads[g_active] : NULL;
    g_state.connected = pad != NULL;
    if (pad) {
        const char *name = p_SDL_GetGamepadName(pad);
        g_state.family = family_of(pad);
        g_state.name = name ? name : "";
    }

    /* Out of focus, or unplugged: everything lets go, so a held button can't walk the character off a cliff. */
    if (!pad || !accept_input) {
        for (b = 0; b < BTN_COUNT; b++)
            set_button(queue, b, 0);
        g_state.lx = g_state.ly = g_state.rx = g_state.ry = g_state.lt = g_state.rt = 0.0f;
        return;
    }

    for (b = 0; b < BTN_LT; b++)
        set_button(queue, b, p_SDL_GetGamepadButton(pad, BUTTON_MAP[b]));
    g_state.lt = axis(pad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER);
    g_state.rt = axis(pad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER);
    set_button(queue, BTN_LT, logic_trigger_held(g_held[BTN_LT], g_state.lt));
    set_button(queue, BTN_RT, logic_trigger_held(g_held[BTN_RT], g_state.rt));

    /* SDL's Y axes grow downward. */
    logic_stick(axis(pad, SDL_GAMEPAD_AXIS_LEFTX), -axis(pad, SDL_GAMEPAD_AXIS_LEFTY), DEADZONE,
                &g_state.lx, &g_state.ly);
    logic_stick(axis(pad, SDL_GAMEPAD_AXIS_RIGHTX), -axis(pad, SDL_GAMEPAD_AXIS_RIGHTY), DEADZONE,
                &g_state.rx, &g_state.ry);
}

const struct PadState *pad_state(void)
{
    return &g_state;
}

void pad_rumble(unsigned short low, unsigned short high, unsigned milliseconds)
{
    if (g_ready && g_active >= 0 && g_pads[g_active])
        p_SDL_RumbleGamepad(g_pads[g_active], low, high, milliseconds);
}
