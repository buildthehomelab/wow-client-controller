/* Controller maths and the button event queue. No Windows or SDL here, so tests run on any machine. */
#ifndef LOGIC_H
#define LOGIC_H

enum PadButton {
    BTN_SOUTH, BTN_EAST, BTN_WEST, BTN_NORTH,
    BTN_BACK, BTN_GUIDE, BTN_START,
    BTN_L3, BTN_R3, BTN_LB, BTN_RB,
    BTN_UP, BTN_DOWN, BTN_LEFT, BTN_RIGHT,
    BTN_LT, BTN_RT,
    BTN_COUNT
};

const char *logic_button_name(int button);

/* Radial deadzone: inside it the stick reads 0, outside it the range is rescaled to reach 1 smoothly. */
void logic_stick(float x, float y, float deadzone, float *out_x, float *out_y);

/* A trigger counts as a button, with a gap between its press and release points so it can't chatter. */
int logic_trigger_held(int was_held, float value);

/* Whole pixels to move this tick. The fraction carries over in *carry, so slow stick movement isn't lost. */
int logic_mouse_step(float stick, float pixels_per_second, float seconds, float *carry);

#define EVENT_QUEUE_SIZE 128

struct PadEvent {
    unsigned char button;
    unsigned char down;
};

struct EventQueue {
    struct PadEvent items[EVENT_QUEUE_SIZE];
    unsigned head, count;
};

/* When full, the oldest event goes: the newest state of a button matters most. */
void queue_push(struct EventQueue *q, int button, int down);
int queue_pop(struct EventQueue *q, struct PadEvent *out);

#endif
