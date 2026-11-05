/* cc -Isrc tests/test_logic.c src/logic.c -o /tmp/test_logic && /tmp/test_logic */
#include "logic.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures, checks;

static void check(int ok, const char *what)
{
    checks++;
    if (!ok) {
        failures++;
        printf("FAIL %s\n", what);
    }
}

static int near(float a, float b)
{
    return fabsf(a - b) < 0.01f;
}

int main(void)
{
    float x, y, carry = 0.0f, total = 0.0f;
    int i, moved = 0;
    struct EventQueue q;
    struct PadEvent e;

    logic_stick(0.1f, 0.1f, 0.18f, &x, &y);
    check(x == 0.0f && y == 0.0f, "inside the deadzone reads 0");
    logic_stick(1.0f, 0.0f, 0.18f, &x, &y);
    check(near(x, 1.0f) && near(y, 0.0f), "full tilt reads 1");
    logic_stick(0.19f, 0.0f, 0.18f, &x, &y);
    check(x > 0.0f && x < 0.05f, "just outside the deadzone starts near 0");
    logic_stick(1.0f, 1.0f, 0.18f, &x, &y);
    check(near(x * x + y * y, 1.0f), "a corner stays length 1");
    check(near(x, y), "a corner keeps its direction");
    logic_stick(-1.0f, 0.0f, 0.18f, &x, &y);
    check(near(x, -1.0f), "negative direction kept");
    logic_stick(0.5f, 0.5f, 1.0f, &x, &y);
    check(x == 0.0f, "a deadzone of 1 can't divide by zero");

    check(!logic_trigger_held(0, 0.3f), "trigger not pressed below the press point");
    check(logic_trigger_held(0, 0.5f), "trigger pressed");
    check(logic_trigger_held(1, 0.3f), "trigger stays held in the gap");
    check(!logic_trigger_held(1, 0.2f), "trigger released");

    for (i = 0; i < 1000; i++)
        moved += logic_mouse_step(0.1f, 900.0f, 0.001f, &carry);
    check(moved == 8 || moved == 9, "slow stick movement adds up through the fractions");
    carry = 0.0f;
    moved = logic_mouse_step(-1.0f, 900.0f, 0.01f, &carry);
    check(moved == -9, "full tilt negative moves the other way");
    total = (float)logic_mouse_step(0.0f, 900.0f, 0.1f, &carry);
    check(total == 0.0f, "no stick, no movement");

    memset(&q, 0, sizeof(q));
    check(!queue_pop(&q, &e), "empty queue");
    queue_push(&q, BTN_LB, 1);
    queue_push(&q, BTN_RB, 0);
    check(queue_pop(&q, &e) && e.button == BTN_LB && e.down == 1, "first out");
    check(queue_pop(&q, &e) && e.button == BTN_RB && e.down == 0, "second out");
    for (i = 0; i < EVENT_QUEUE_SIZE + 3; i++)
        queue_push(&q, i % BTN_COUNT, 1);
    check(q.count == EVENT_QUEUE_SIZE, "overflow keeps the size");
    check(queue_pop(&q, &e) && e.button == (3 % BTN_COUNT), "overflow drops the oldest");

    check(strcmp(logic_button_name(BTN_SOUTH), "SOUTH") == 0, "south name");
    check(strcmp(logic_button_name(BTN_RT), "RT") == 0, "rt name");
    check(strcmp(logic_button_name(99), "") == 0, "bad button name");

    check(logic_key_vk("Q") == 'Q', "a letter is its own key");
    check(logic_key_vk("7") == '7', "a digit is its own key");
    check(logic_key_vk("F1") == 0x70 && logic_key_vk("F12") == 0x7B, "function keys");
    check(logic_key_vk("F0") == 0 && logic_key_vk("F25") == 0 && logic_key_vk("F1X") == 0, "no such function key");
    check(logic_key_vk("NUMPAD0") == 0x60 && logic_key_vk("NUMPAD9") == 0x69, "numpad digits");
    check(logic_key_vk("NUMPADPLUS") == 0x6B, "numpad plus");
    check(logic_key_vk("BUTTON4") == 0x05 && logic_key_vk("BUTTON3") == 0x04, "side and middle mouse buttons");
    check(logic_key_vk("BUTTON1") == 0 && logic_key_vk("MOUSEWHEELUP") == 0, "keys that can't be held");
    check(logic_key_vk("SPACE") == 0x20 && logic_key_vk("PAGEDOWN") == 0x22, "named keys");
    check(logic_key_vk("-") == -'-' && logic_key_vk("[") == -'[', "punctuation asks the layout");
    check(logic_key_vk("") == 0 && logic_key_vk(0) == 0 && logic_key_vk("q") == 0, "nothing for nonsense");
    check(logic_key_vk("SHIFT-Q") == 0, "modifiers aren't part of the name");

    printf("%d checks, %d failures\n", checks, failures);
    return failures != 0;
}
