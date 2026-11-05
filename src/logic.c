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
