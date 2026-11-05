/* The DLL links no C runtime. Wow.exe imports msacm32 directly, so a dependency Windows can't find would stop the game
   starting for everyone, and older Windows may not have the UCRT. kernel32 and user32 are all it imports. The compiler
   can still emit calls to these two. */
#include <stddef.h>

void *memset(void *destination, int value, size_t size)
{
    volatile unsigned char *d = destination;
    while (size--)
        *d++ = (unsigned char)value;
    return destination;
}

void *memcpy(void *destination, const void *source, size_t size)
{
    volatile unsigned char *d = destination;
    const unsigned char *s = source;
    while (size--)
        *d++ = *s++;
    return destination;
}
