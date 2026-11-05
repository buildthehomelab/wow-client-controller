/* Every controller goes through SDL3. SDL3.dll is loaded at run time, so a missing or broken copy only turns
   controllers off: it can never stop the game starting. */
#ifndef PAD_H
#define PAD_H

#include "logic.h"

struct PadState {
    int connected;
    const char *family; /* button art: "ltr" Xbox, "shp" PlayStation, "rev" Nintendo, "gen" anything else */
    const char *name;
    float lx, ly, rx, ry; /* after the deadzone; up and right are positive */
    float lt, rt;
};

/* Asks Windows whether anything controller-like is plugged in, without loading SDL. */
int pad_device_present(void);
int pad_init(const char *directory);
void pad_update(struct EventQueue *queue, int accept_input);
const struct PadState *pad_state(void);
void pad_rumble(unsigned short low, unsigned short high, unsigned milliseconds);

#endif
