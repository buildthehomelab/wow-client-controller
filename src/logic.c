#include "logic.h"

static const char *const BUTTON_NAMES[BTN_COUNT] = {
    "SOUTH", "EAST", "WEST", "NORTH",
    "BACK", "GUIDE", "START",
    "L3", "R3", "LB", "RB",
    "UP", "DOWN", "LEFT", "RIGHT",
    "LT", "RT",
};

const char *logic_button_name(int button)
{
    return (button >= 0 && button < BTN_COUNT) ? BUTTON_NAMES[button] : "";
}

/* No libm: the DLL stays small and this only needs a rough root. */
static float root(float v)
{
    float r = v > 1.0f ? v : 1.0f;
    int i;
    if (v <= 0.0f)
        return 0.0f;
    for (i = 0; i < 12; i++)
        r = 0.5f * (r + v / r);
    return r;
}

void logic_stick(float x, float y, float deadzone, float *out_x, float *out_y)
{
    float length = root(x * x + y * y);
    float scaled;
    if (length <= deadzone || deadzone >= 1.0f) {
        *out_x = 0.0f;
        *out_y = 0.0f;
        return;
    }
    scaled = (length - deadzone) / (1.0f - deadzone);
    if (scaled > 1.0f)
        scaled = 1.0f;
    *out_x = x / length * scaled;
    *out_y = y / length * scaled;
}

int logic_trigger_held(int was_held, float value)
{
    return was_held ? value > 0.25f : value > 0.40f;
}

int logic_mouse_step(float stick, float pixels_per_second, float seconds, float *carry)
{
    /* Squared response: small tilts aim finely, a full tilt turns fast. */
    float amount = stick * (stick < 0.0f ? -stick : stick) * pixels_per_second * seconds + *carry;
    int whole = (int)amount;
    *carry = amount - (float)whole;
    return whole;
}

static int same(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return *a == *b;
}

/* A number from 1 to 99 and nothing after it, else 0. */
static int small_number(const char *text)
{
    int value = 0, digits = 0;
    while (*text >= '0' && *text <= '9' && digits < 2) {
        value = value * 10 + (*text - '0');
        text++;
        digits++;
    }
    return (*text || !digits) ? 0 : value;
}

static int starts(const char *text, const char *prefix, const char **rest)
{
    while (*prefix && *text == *prefix) {
        text++;
        prefix++;
    }
    if (*prefix)
        return 0;
    *rest = text;
    return 1;
}

/* Windows' own numbers, written out so this file needs no Windows headers. */
static const struct { const char *name; int vk; } NAMED_KEYS[] = {
    { "SPACE", 0x20 }, { "PAGEUP", 0x21 }, { "PAGEDOWN", 0x22 }, { "END", 0x23 }, { "HOME", 0x24 },
    { "LEFT", 0x25 }, { "UP", 0x26 }, { "RIGHT", 0x27 }, { "DOWN", 0x28 }, { "INSERT", 0x2D }, { "DELETE", 0x2E },
    { "BACKSPACE", 0x08 }, { "TAB", 0x09 }, { "ENTER", 0x0D }, { "PAUSE", 0x13 }, { "CAPSLOCK", 0x14 },
    { "NUMLOCK", 0x90 }, { "SCROLLLOCK", 0x91 }, { "PRINTSCREEN", 0x2C },
    { "NUMPADMULTIPLY", 0x6A }, { "NUMPADPLUS", 0x6B }, { "NUMPADMINUS", 0x6D }, { "NUMPADDECIMAL", 0x6E },
    { "NUMPADDIVIDE", 0x6F },
    { "BUTTON3", 0x04 }, { "MIDDLEBUTTON", 0x04 }, { "BUTTON4", 0x05 }, { "BUTTON5", 0x06 },
};

int logic_key_vk(const char *name)
{
    const char *rest;
    int number;
    unsigned i;
    if (!name || !name[0])
        return 0;
    if (!name[1]) {
        char c = name[0];
        if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            return c;
        if (c > ' ' && c < 127 && !(c >= 'a' && c <= 'z'))
            return -c;
        return 0;
    }
    for (i = 0; i < sizeof(NAMED_KEYS) / sizeof(NAMED_KEYS[0]); i++)
        if (same(name, NAMED_KEYS[i].name))
            return NAMED_KEYS[i].vk;
    if (starts(name, "NUMPAD", &rest) && rest[0] >= '0' && rest[0] <= '9' && !rest[1])
        return 0x60 + (rest[0] - '0');
    if (starts(name, "F", &rest) && (number = small_number(rest)) >= 1 && number <= 24)
        return 0x70 + number - 1;
    return 0;
}

void queue_push(struct EventQueue *q, int button, int down)
{
    unsigned slot;
    if (q->count == EVENT_QUEUE_SIZE) {
        q->head = (q->head + 1) % EVENT_QUEUE_SIZE;
        q->count--;
    }
    slot = (q->head + q->count) % EVENT_QUEUE_SIZE;
    q->items[slot].button = (unsigned char)button;
    q->items[slot].down = (unsigned char)(down != 0);
    q->count++;
}

int queue_pop(struct EventQueue *q, struct PadEvent *out)
{
    if (q->count == 0)
        return 0;
    *out = q->items[q->head];
    q->head = (q->head + 1) % EVENT_QUEUE_SIZE;
    q->count--;
    return 1;
}
