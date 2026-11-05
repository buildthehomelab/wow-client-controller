/* Puts controller support into the game with no addon: reads the pad through SDL, then runs the embedded Lua UI as
   the client's own code, which is what lets it cast and move in combat. See README.md. */
#include "client.h"
#include "log.h"
#include "logic.h"
#include "pad.h"

#include <windows.h>

/* Files built into the DLL. */
#define EMBED(symbol, path)                 \
    __asm__(".section .rdata,\"dr\"\n"      \
            ".globl _" #symbol "\n"         \
            "_" #symbol ":\n"               \
            ".incbin \"" path "\"\n"        \
            ".globl _" #symbol "_end\n"     \
            "_" #symbol "_end:\n"           \
            ".byte 0\n"                     \
            ".text\n");                     \
    extern const char symbol[], symbol##_end[];

EMBED(lua_atlas, "lua/atlas.lua")
EMBED(lua_core, "lua/core.lua")
EMBED(lua_actions, "lua/actions.lua")
EMBED(lua_radial, "lua/radial.lua")
EMBED(lua_cursor, "lua/cursor.lua")
EMBED(lua_hud, "lua/hud.lua")
EMBED(lua_world, "lua/world.lua")
EMBED(lua_glue, "lua/glue.lua")
EMBED(lua_api, "lua/api.lua")
EMBED(art_ltr, "art/ltr.blp")
EMBED(art_shp, "art/shp.blp")
EMBED(art_rev, "art/rev.blp")
EMBED(art_gen, "art/gen.blp")

#define PAD_CHECK_TICKS 120

static char g_game_directory[MAX_PATH];
static char g_dll_directory[MAX_PATH];
static FrameHandler g_original_handler;
static struct EventQueue g_events;
static HWND g_window;
static int g_started;
static int g_pad_ok, g_pad_failed, g_pad_check;
static LARGE_INTEGER g_clock_rate, g_clock_last;

/* Set only while tick() is running the UI's frame function. Clearing taint needs this, so nothing an addon can call at
   any other time can clear it. */
static int g_in_frame;
static int g_starting;

static float g_stick_speed_x, g_stick_speed_y;
static float g_carry_x, g_carry_y;
static int g_mouse_held[2]; /* left, right */

/* ---- window ---------------------------------------------------------------------------------------------- */

static BOOL CALLBACK find_window(HWND window, LPARAM context)
{
    static const char PREFIX[] = "GxWindowClass";
    DWORD process = 0;
    char class_name[32] = "";
    int i;
    GetWindowThreadProcessId(window, &process);
    if (process != GetCurrentProcessId())
        return TRUE;
    GetClassNameA(window, class_name, sizeof(class_name));
    for (i = 0; PREFIX[i]; i++)
        if (class_name[i] != PREFIX[i])
            return TRUE;
    *(HWND *)context = window;
    return FALSE;
}

static HWND game_window(void)
{
    if (!g_window || !IsWindow(g_window)) {
        g_window = NULL;
        EnumWindows(find_window, (LPARAM)&g_window);
    }
    return g_window;
}

static int game_in_front(void)
{
    HWND window = game_window();
    return window && GetForegroundWindow() == window;
}

/* ---- synthetic mouse ------------------------------------------------------------------------------------- */

static void mouse_event_send(DWORD flags, LONG dx, LONG dy, DWORD data)
{
    INPUT input;
    SecureZeroMemory(&input, sizeof(input));
    input.type = INPUT_MOUSE;
    input.mi.dx = dx;
    input.mi.dy = dy;
    input.mi.mouseData = data;
    input.mi.dwFlags = flags;
    SendInput(1, &input, sizeof(input));
}

/* These are real mouse buttons, held for the whole desktop. So every press is remembered here and always let go, in or
   out of focus, whatever has become of the Lua that pressed it. */
static void mouse_button(int which, int down)
{
    static const DWORD FLAGS[2][2] = {
        { MOUSEEVENTF_LEFTUP, MOUSEEVENTF_LEFTDOWN },
        { MOUSEEVENTF_RIGHTUP, MOUSEEVENTF_RIGHTDOWN },
    };
    down = down != 0;
    if (g_mouse_held[which] == down)
        return;
    g_mouse_held[which] = down;
    mouse_event_send(FLAGS[which][down], 0, 0, 0);
}

static void release_mouse(void)
{
    mouse_button(0, 0);
    mouse_button(1, 0);
}

static void stick_off(void)
{
    g_stick_speed_x = g_stick_speed_y = 0.0f;
    g_carry_x = g_carry_y = 0.0f;
}

/* ---- world scan: what the interact button would act on --------------------------------------------------- */

struct ScanResult {
    void *player;
    float x, y, z;
    float best;
    uint64_t guid;
    const char *kind;
};

static int gameobject_usable(uint32_t type)
{
    switch (type) {
    case 1:  /* button */
    case 2:  /* quest giver */
    case 3:  /* chest, herb, ore */
    case 10: /* goober */
    case 17: /* fishing bobber */
    case 19: /* mailbox */
    case 22: /* spellcaster */
    case 23: /* meeting stone */
    case 24: /* flag stand */
    case 25: /* fishing hole */
    case 26: /* flag drop */
    case 32: /* barber chair */
    case 34: /* guild bank */
        return 1;
    default:
        return 0;
    }
}

static int __cdecl scan_object(uint64_t guid, void *context)
{
    struct ScanResult *scan = (struct ScanResult *)context;
    void *object = GetObjectByGuid(guid, TYPEMASK_ANY, "", 0);
    const uint32_t *fields;
    uint32_t type;
    const char *kind = NULL;
    float position[3], dx, dy, dz, distance;

    if (!object || object == scan->player)
        return 1;
    fields = *(const uint32_t **)((const char *)object + 8);
    if (!fields)
        return 1;
    type = fields[FIELD_OBJECT_TYPE];

    if (type & TYPEMASK_UNIT) {
        uint32_t flags = fields[FIELD_UNIT_FLAGS];
        if (flags & UNIT_FLAG_NOT_SELECTABLE)
            return 1;
        if (fields[FIELD_UNIT_HEALTH] == 0) {
            if (fields[FIELD_UNIT_DYNAMIC_FLAGS] & UNIT_DYNFLAG_LOOTABLE)
                kind = "loot";
            else if (flags & UNIT_FLAG_SKINNABLE)
                kind = "use";
        } else if (fields[FIELD_UNIT_NPC_FLAGS] != 0 && ClientUnitReaction(object, scan->player) >= 3) {
            kind = "talk";
        }
    } else if (type & TYPEMASK_GAMEOBJECT) {
        uint32_t bytes = fields[FIELD_GO_BYTES_1];
        if (!(fields[FIELD_GO_FLAGS] & GO_FLAG_NOT_SELECTABLE) && gameobject_usable((bytes >> 8) & 0xFF))
            kind = "use";
    }
    if (!kind)
        return 1;

    ((GetPositionFn)(*(void ***)object)[VTABLE_GET_POSITION])(object, position);
    dx = position[0] - scan->x;
    dy = position[1] - scan->y;
    dz = position[2] - scan->z;
    distance = dx * dx + dy * dy + dz * dz;
    /* A corpse with loot wins over the vendor standing beside it. */
    if (kind[0] == 'l')
        distance *= 0.5f;
    if (distance < scan->best) {
        scan->best = distance;
        scan->guid = guid;
        scan->kind = kind;
    }
    return 1;
}

/* ---- functions Lua can call ------------------------------------------------------------------------------ */

static int l_poll(lua_State *L)
{
    const struct PadState *state = pad_state();
    lua_pushboolean(L, state->connected);
    lua_pushstring(L, state->family);
    lua_pushnumber(L, state->lx);
    lua_pushnumber(L, state->ly);
    lua_pushnumber(L, state->rx);
    lua_pushnumber(L, state->ry);
    lua_pushnumber(L, state->lt);
    lua_pushnumber(L, state->rt);
    lua_pushboolean(L, game_in_front());
    return 9;
}

static int l_in_world(lua_State *L)
{
    lua_pushboolean(L, CLIENT_IN_WORLD != 0);
    return 1;
}

static int l_name(lua_State *L)
{
    lua_pushstring(L, pad_state()->name);
    return 1;
}

static int l_next_event(lua_State *L)
{
    struct PadEvent event;
    if (!queue_pop(&g_events, &event))
        return 0;
    lua_pushstring(L, logic_button_name(event.button));
    lua_pushboolean(L, event.down);
    return 2;
}

/* The right stick moves the mouse: the camera while mouselooking, the cursor otherwise. Speeds are pixels per
   second at full tilt. Speed 0 switches it off. */
static int l_stick_mouse(lua_State *L)
{
    g_stick_speed_x = (float)lua_tonumber(L, 1);
    g_stick_speed_y = (float)lua_tonumber(L, 2);
    return 0;
}

/* Places the cursor by share of the window, x from the left and y from the bottom. */
static int l_set_cursor(lua_State *L)
{
    HWND window;
    RECT client;
    POINT point;
    if (!game_in_front())
        return 0;
    window = game_window();
    if (!window || !GetClientRect(window, &client))
        return 0;
    point.x = (LONG)(lua_tonumber(L, 1) * (double)client.right);
    point.y = (LONG)((1.0 - lua_tonumber(L, 2)) * (double)client.bottom);
    ClientToScreen(window, &point);
    SetCursorPos(point.x, point.y);
    return 0;
}

static int l_mouse_button(lua_State *L)
{
    const char *which = lua_tolstring(L, 1, NULL);
    int down = lua_toboolean(L, 2);
    if (!which)
        return 0;
    /* A press needs focus. A release never does. */
    if (down && !game_in_front())
        return 0;
    mouse_button(which[0] == 'r' ? 1 : 0, down);
    return 0;
}

static int l_wheel(lua_State *L)
{
    if (!game_in_front())
        return 0;
    mouse_event_send(MOUSEEVENTF_WHEEL, 0, 0, (DWORD)(LONG)(lua_tonumber(L, 1) * WHEEL_DELTA));
    return 0;
}

/* Nearest thing to interact with within the given range: kind ("loot", "talk", "use"), guid high, guid low. */
static int l_scan_interact(lua_State *L)
{
    struct ScanResult scan;
    double range = lua_tonumber(L, 1);
    float position[3];
    SecureZeroMemory(&scan, sizeof(scan));
    if (ActivePlayerGuid() == 0)
        return 0;
    scan.player = GetObjectByGuid(ActivePlayerGuid(), TYPEMASK_UNIT, "", 0);
    if (!scan.player)
        return 0;
    ((GetPositionFn)(*(void ***)scan.player)[VTABLE_GET_POSITION])(scan.player, position);
    scan.x = position[0];
    scan.y = position[1];
    scan.z = position[2];
    scan.best = (float)(range * range);
    EnumVisibleObjects(scan_object, &scan);
    if (!scan.kind)
        return 0;
    lua_pushstring(L, scan.kind);
    lua_pushnumber(L, (double)(uint32_t)(scan.guid >> 32));
    lua_pushnumber(L, (double)(uint32_t)scan.guid);
    return 3;
}

/* Goes through l_call: selecting the object checks taint (0x524C6F). */
static int l_interact(lua_State *L)
{
    uint64_t guid = ((uint64_t)(uint32_t)lua_tonumber(L, 1) << 32) | (uint32_t)lua_tonumber(L, 2);
    /* Only what's still in the world: the scan's result can be a moment old. */
    if (guid && GetObjectByGuid(guid, TYPEMASK_ANY, "", 0))
        lua_pushboolean(L, InteractWithGuid(guid));
    else
        lua_pushboolean(L, 0);
    return 1;
}

/* Call(function, ...): runs a protected game function with a clean taint, for the function and its arguments. Reading
   almost anything an addon has touched taints the running code, however innocent the read, and that's all a taint in
   our code ever means. Out of the frame function it's a plain call, so this can't clean anything for anyone else. */
static int l_call(lua_State *L)
{
    int arguments = lua_gettop(L) - 1;
    uint32_t taint = CLIENT_TAINT;
    int failed;
    if (arguments < 0)
        return 0;
    if (g_in_frame || g_starting) {
        char *slot;
        for (slot = LUA_STATE_BASE(L); slot < LUA_STATE_TOP(L); slot += LUA_VALUE_SIZE)
            LUA_VALUE_TAINT(slot) = 0;
        CLIENT_TAINT = 0;
    }
    failed = lua_pcall(L, arguments, LUA_MULTRET, 0);
    if (g_in_frame || g_starting)
        CLIENT_TAINT = taint;
    if (failed) {
        const char *message = lua_tolstring(L, -1, NULL);
        log_line("error in call: %s", message ? message : "?");
        return 0;
    }
    return lua_gettop(L);
}

/* Try(function, ...): true, or false and the message. In here rather than pcall, which an addon can replace, and which
   would then be handed every function we protect. */
static int l_try(lua_State *L)
{
    int arguments = lua_gettop(L) - 1;
    char message[256] = "";
    int failed;
    if (arguments < 0)
        return 0;
    failed = lua_pcall(L, arguments, LUA_MULTRET, 0);
    if (failed) {
        const char *text = lua_tolstring(L, -1, NULL);
        lstrcpynA(message, text ? text : "?", sizeof(message));
    }
    lua_settop(L, 0);
    lua_pushboolean(L, !failed);
    if (failed) {
        lua_pushstring(L, message);
        return 2;
    }
    return 1;
}

/* Global(name): the value, and whether it's clean. Only while starting does this clear the running taint. An addon can
   have replaced any global before we load (addons load first), and reading one that it has taints the code, which then
   stamps its taint on every value it copies: the next, perfectly good, function we read would look tainted too. */
static int l_global(lua_State *L)
{
    const char *name = lua_tolstring(L, 1, NULL);
    uint32_t value_taint;
    if (!name)
        return 0;
    if (g_starting)
        CLIENT_TAINT = 0;
    lua_getfield(L, LUA_GLOBALSINDEX, name);
    value_taint = LUA_VALUE_TAINT(LUA_STATE_TOP(L) - LUA_VALUE_SIZE);
    if (g_starting)
        CLIENT_TAINT = 0;
    lua_pushboolean(L, value_taint == 0);
    return 2;
}

/* A slash command or an addon's request can arrive from code an addon has tainted, and anything it wrote into our
   tables would stay tainted for good. So its text waits here, and the frame function picks up a clean copy. A few can
   wait at once, so an addon's request and the player's command in the same frame both arrive; past that, the newest
   are dropped. */
#define COMMAND_SLOTS 8
static char g_commands[COMMAND_SLOTS][256];
static unsigned g_command_first, g_command_count;

static int l_post_command(lua_State *L)
{
    const char *text = lua_tolstring(L, 1, NULL);
    if (g_command_count == COMMAND_SLOTS)
        return 0;
    lstrcpynA(g_commands[(g_command_first + g_command_count) % COMMAND_SLOTS], text ? text : "", 256);
    g_command_count++;
    return 0;
}

static int l_next_command(lua_State *L)
{
    if (g_command_count == 0)
        return 0;
    lua_pushstring(L, g_commands[g_command_first]);
    g_command_first = (g_command_first + 1) % COMMAND_SLOTS;
    g_command_count--;
    return 1;
}

static int l_rumble(lua_State *L)
{
    pad_rumble((unsigned short)(lua_tonumber(L, 1) * 65535.0), (unsigned short)(lua_tonumber(L, 2) * 65535.0),
               (unsigned)lua_tonumber(L, 3));
    return 0;
}

static int l_log(lua_State *L)
{
    const char *text = lua_tolstring(L, 1, NULL);
    if (text)
        log_line("%s", text);
    return 0;
}

static void settings_path(char *path)
{
    wsprintfA(path, "%s\\WTF\\Controller.txt", g_game_directory);
}

static int l_load_settings(lua_State *L)
{
    static char text[4096]; /* not on the stack: a page or more would need the C runtime's stack probe */
    char path[MAX_PATH + 32];
    DWORD got = 0;
    HANDLE file;
    settings_path(path);
    file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return 0;
    ReadFile(file, text, sizeof(text) - 1, &got, NULL);
    CloseHandle(file);
    text[got] = 0;
    lua_pushstring(L, text);
    return 1;
}

static int l_save_settings(lua_State *L)
{
    char path[MAX_PATH + 32];
    size_t length = 0;
    const char *text;
    DWORD written;
    HANDLE file;
    text = lua_tolstring(L, 1, &length);
    if (!text || length > 4000)
        return 0;
    settings_path(path);
    file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return 0;
    WriteFile(file, text, (DWORD)length, &written, NULL);
    CloseHandle(file);
    return 0;
}

/* Keeps the UI's frame function in the registry, out of addons' reach. A frame's OnUpdate would not be:
   EnumerateFrames and GetScript hand it to anyone. */
static int l_set_driver(lua_State *L)
{
    lua_settop(L, 1);
    lua_setfield(L, LUA_REGISTRYINDEX, "GamepadDriver");
    return 0;
}

/* ---- starting ---------------------------------------------------------------------------------------------*/

static const struct { const char *name; lua_CFunction function; } NATIVE_FUNCTIONS[] = {
    { "Poll", l_poll },
    { "Name", l_name },
    { "InWorld", l_in_world },
    { "NextEvent", l_next_event },
    { "StickMouse", l_stick_mouse },
    { "SetCursor", l_set_cursor },
    { "MouseButton", l_mouse_button },
    { "Wheel", l_wheel },
    { "ScanInteract", l_scan_interact },
    { "Interact", l_interact },
    { "Call", l_call },
    { "Try", l_try },
    { "Global", l_global },
    { "PostCommand", l_post_command },
    { "NextCommand", l_next_command },
    { "Rumble", l_rumble },
    { "Log", l_log },
    { "LoadSettings", l_load_settings },
    { "SaveSettings", l_save_settings },
    { "SetDriver", l_set_driver },
};

static int lua_field_exists(lua_State *L, int table, const char *name)
{
    int exists;
    lua_getfield(L, table, name);
    exists = lua_type(L, -1) != LUA_TNIL;
    lua_settop(L, -2);
    return exists;
}

/* Each file gets the native functions and a table the files share as its arguments. There are no globals, so at no
   point in loading can an addon see them. */
static void run_file(lua_State *L, const char *code, const char *end, const char *name)
{
    /* One tainted read in the last file mustn't carry over into this one. */
    CLIENT_TAINT = 0;
    if (luaL_loadbuffer(L, code, (size_t)(end - code), name) != 0) {
        const char *message = lua_tolstring(L, -1, NULL);
        log_line("error compiling %s: %s", name, message ? message : "?");
        lua_settop(L, -2);
        return;
    }
    lua_pushvalue(L, -3);
    lua_pushvalue(L, -3);
    if (lua_pcall(L, 2, 0, 0) != 0) {
        const char *message = lua_tolstring(L, -1, NULL);
        log_line("error in %s: %s", name, message ? message : "?");
        lua_settop(L, -2);
    }
}

static void start_ui(lua_State *L, int in_game)
{
    size_t i;
    uint32_t taint = CLIENT_TAINT;
    int depth = CLIENT_TAINT_DEPTH;
    int top = lua_gettop(L);

    /* A request left from the UI before a reload or logout was meant for that one. */
    g_command_first = g_command_count = 0;

    CLIENT_TAINT_DEPTH = depth + 1;
    g_starting = 1;
    CLIENT_TAINT = 0;
    CLIENT_FUNCTION_RANGE_LOW = 1;
    CLIENT_FUNCTION_RANGE_HIGH = 0x7FFFFFFF;

    /* Set first: an error in the UI below must not make it start over on every frame. */
    lua_pushboolean(L, 1);
    lua_setfield(L, LUA_REGISTRYINDEX, "GamepadStarted");

    lua_createtable(L, 0, (int)(sizeof(NATIVE_FUNCTIONS) / sizeof(NATIVE_FUNCTIONS[0])));
    for (i = 0; i < sizeof(NATIVE_FUNCTIONS) / sizeof(NATIVE_FUNCTIONS[0]); i++) {
        lua_pushcclosure(L, NATIVE_FUNCTIONS[i].function, 0);
        lua_setfield(L, -2, NATIVE_FUNCTIONS[i].name);
    }
    lua_createtable(L, 0, 32);

    log_line("starting %s UI", in_game ? "game" : "login");
    if (in_game) {
        run_file(L, lua_atlas, lua_atlas_end, "@Controller\\atlas.lua");
        run_file(L, lua_core, lua_core_end, "@Controller\\core.lua");
        run_file(L, lua_actions, lua_actions_end, "@Controller\\actions.lua");
        run_file(L, lua_radial, lua_radial_end, "@Controller\\radial.lua");
        run_file(L, lua_cursor, lua_cursor_end, "@Controller\\cursor.lua");
        run_file(L, lua_hud, lua_hud_end, "@Controller\\hud.lua");
        run_file(L, lua_world, lua_world_end, "@Controller\\world.lua");
        run_file(L, lua_api, lua_api_end, "@Controller\\api.lua");
    } else {
        run_file(L, lua_glue, lua_glue_end, "@Controller\\glue.lua");
    }
    lua_settop(L, top);
    g_starting = 0;
    CLIENT_TAINT = taint;
    CLIENT_TAINT_DEPTH = depth;
}

/* The button art is unpacked next to where addons keep theirs, because the launcher leaves Interface alone and
   the client reads loose files there. Written only when missing or a different size. */
static void write_art(const char *name, const char *start, const char *end)
{
    char path[MAX_PATH + 64];
    DWORD size = (DWORD)(end - start), written;
    WIN32_FILE_ATTRIBUTE_DATA info;
    HANDLE file;

    wsprintfA(path, "%s\\Interface\\GamePad\\%s.blp", g_game_directory, name);
    if (GetFileAttributesExA(path, GetFileExInfoStandard, &info) && info.nFileSizeLow == size)
        return;
    file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        log_line("could not write %s (error %lu)", path, GetLastError());
        return;
    }
    WriteFile(file, start, size, &written, NULL);
    CloseHandle(file);
}

static void write_all_art(void)
{
    char path[MAX_PATH + 32];
    wsprintfA(path, "%s\\Interface", g_game_directory);
    CreateDirectoryA(path, NULL);
    wsprintfA(path, "%s\\Interface\\GamePad", g_game_directory);
    CreateDirectoryA(path, NULL);
    write_art("ltr", art_ltr, art_ltr_end);
    write_art("shp", art_shp, art_shp_end);
    write_art("rev", art_rev, art_rev_end);
    write_art("gen", art_gen, art_gen_end);
}

/* ---- every frame ----------------------------------------------------------------------------------------- */

static void apply_stick(float seconds)
{
    const struct PadState *state = pad_state();
    int dx, dy;
    if (g_stick_speed_x == 0.0f && g_stick_speed_y == 0.0f)
        return;
    dx = logic_mouse_step(state->rx, g_stick_speed_x, seconds, &g_carry_x);
    dy = logic_mouse_step(-state->ry, g_stick_speed_y, seconds, &g_carry_y);
    if (dx || dy)
        mouse_event_send(MOUSEEVENTF_MOVE, dx, dy, 0);
}

static void run_frame_function(lua_State *L, float seconds)
{
    static int errors;
    int top = lua_gettop(L);
    int depth = CLIENT_TAINT_DEPTH;
    uint32_t taint = CLIENT_TAINT;

    CLIENT_TAINT_DEPTH = depth + 1;
    CLIENT_TAINT = 0;
    lua_getfield(L, LUA_REGISTRYINDEX, "GamepadDriver");
    if (lua_type(L, -1) != LUA_TNIL) {
        lua_pushnumber(L, seconds);
        g_in_frame = 1;
        if (lua_pcall(L, 1, 0, 0) != 0 && errors < 20) {
            const char *message = lua_tolstring(L, -1, NULL);
            errors++;
            log_line("error in frame: %s", message ? message : "?");
        }
        g_in_frame = 0;
    }
    lua_settop(L, top);
    CLIENT_TAINT = taint;
    CLIENT_TAINT_DEPTH = depth;
}

static void tick(void)
{
    lua_State *L;
    LARGE_INTEGER now;
    float seconds;
    int in_front;

    if (!g_started) {
        g_started = 1;
        write_all_art();
        QueryPerformanceFrequency(&g_clock_rate);
        QueryPerformanceCounter(&g_clock_last);
    }

    QueryPerformanceCounter(&now);
    seconds = (float)((double)(now.QuadPart - g_clock_last.QuadPart) / (double)g_clock_rate.QuadPart);
    g_clock_last = now;
    if (seconds > 0.1f)
        seconds = 0.1f;

    if (!g_pad_ok && !g_pad_failed && --g_pad_check <= 0) {
        g_pad_check = PAD_CHECK_TICKS;
        if (pad_device_present()) {
            g_pad_ok = pad_init(g_dll_directory);
            g_pad_failed = !g_pad_ok;
        }
    }

    in_front = game_in_front();
    if (!in_front)
        release_mouse();
    if (g_pad_ok) {
        pad_update(&g_events, in_front);
        if (in_front)
            apply_stick(seconds);
    }

    L = GetLuaState();
    if (!L || !lua_field_exists(L, LUA_REGISTRYINDEX, "GamepadStarted")) {
        /* The Lua that was driving these is gone, whether by /reload, logout or a new login screen. */
        stick_off();
        release_mouse();
        if (L) {
            if (lua_field_exists(L, LUA_GLOBALSINDEX, "UIParent"))
                start_ui(L, 1);
            else if (lua_field_exists(L, LUA_GLOBALSINDEX, "CharacterSelect"))
                start_ui(L, 0);
        }
        return;
    }
    run_frame_function(L, seconds);
}

static int __cdecl frame_handler(int a, int b, int c, int d)
{
    tick();
    return g_original_handler(a, b, c, d);
}

/* ---- loading --------------------------------------------------------------------------------------------- */

static void directory_of(HMODULE module, char *out, DWORD size)
{
    char *p, *slash = NULL;
    GetModuleFileNameA(module, out, size);
    for (p = out; *p; p++)
        if (*p == '\\')
            slash = p;
    if (slash)
        *slash = 0;
}

/* Another program in this folder could load this DLL too, and reading a fixed address in it could fault. */
static int host_is_wow(void)
{
    const char *base = (const char *)GetModuleHandleA(NULL);
    const IMAGE_DOS_HEADER *dos = (const IMAGE_DOS_HEADER *)base;
    const IMAGE_NT_HEADERS *nt;
    if ((uintptr_t)base != 0x00400000u || dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    nt = (const IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
    return nt->Signature == IMAGE_NT_SIGNATURE && nt->OptionalHeader.SizeOfImage > ADDR_FRAME_PUSH_OPERAND - 0x00400000u + 4;
}

/* Changes one number in Wow.exe's code in memory. If that number isn't what we expect (a different exe), nothing
   changes and the game runs as if this DLL weren't here. */
static int install(void)
{
    uint32_t *operand = (uint32_t *)(uintptr_t)ADDR_FRAME_PUSH_OPERAND;
    const uint8_t *opcode = (const uint8_t *)operand - 1;
    uint32_t new_value = (uint32_t)(uintptr_t)frame_handler;
    DWORD old_protect;

    if (*opcode != 0x68 || *operand != ADDR_FRAME_HANDLER) {
        log_line("Wow.exe is not the expected build (%02X %08lX); controllers are off", *opcode,
                 (unsigned long)*operand);
        return 0;
    }
    if (!VirtualProtect(operand, 4, PAGE_EXECUTE_READWRITE, &old_protect)) {
        log_line("VirtualProtect failed (%lu); controllers are off", GetLastError());
        return 0;
    }
    g_original_handler = (FrameHandler)(uintptr_t)ADDR_FRAME_HANDLER;
    *operand = new_value;
    VirtualProtect(operand, 4, old_protect, &old_protect);
    FlushInstructionCache(GetCurrentProcess(), operand, 4);
    log_line("frame handler installed");
    return 1;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        if (!host_is_wow())
            return TRUE;
        directory_of(NULL, g_game_directory, sizeof(g_game_directory));
        directory_of(instance, g_dll_directory, sizeof(g_dll_directory));
        log_open(g_game_directory);
        log_line("controller DLL loaded");
        install();
    } else if (reason == DLL_PROCESS_DETACH) {
        release_mouse();
    }
    return TRUE;
}
