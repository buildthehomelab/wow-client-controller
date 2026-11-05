/* Windows loads this file as msacm32.dll, because Wow.exe imports that name and this copy sits next to it. Every
   export jumps to the real msacm32.dll from the system folder, loaded the first time one is used. No edit to
   Wow.exe, and no clash with version.dll (LuxVelum) or dinput8.dll (AwesomeWotlk), which do the same under their
   own names. */
#include <windows.h>

#define PROXY_EXPORTS(X) \
    X(0, acmDriverAddA) X(1, acmDriverAddW) X(2, acmDriverClose) X(3, acmDriverDetailsA) \
    X(4, acmDriverDetailsW) X(5, acmDriverEnum) X(6, acmDriverID) X(7, acmDriverMessage) \
    X(8, acmDriverOpen) X(9, acmDriverPriority) X(10, acmDriverRemove) X(11, acmFilterChooseA) \
    X(12, acmFilterChooseW) X(13, acmFilterDetailsA) X(14, acmFilterDetailsW) X(15, acmFilterEnumA) \
    X(16, acmFilterEnumW) X(17, acmFilterTagDetailsA) X(18, acmFilterTagDetailsW) X(19, acmFilterTagEnumA) \
    X(20, acmFilterTagEnumW) X(21, acmFormatChooseA) X(22, acmFormatChooseW) X(23, acmFormatDetailsA) \
    X(24, acmFormatDetailsW) X(25, acmFormatEnumA) X(26, acmFormatEnumW) X(27, acmFormatSuggest) \
    X(28, acmFormatTagDetailsA) X(29, acmFormatTagDetailsW) X(30, acmFormatTagEnumA) X(31, acmFormatTagEnumW) \
    X(32, acmGetVersion) X(33, acmMessage32) X(34, acmMetrics) X(35, acmStreamClose) X(36, acmStreamConvert) \
    X(37, acmStreamMessage) X(38, acmStreamOpen) X(39, acmStreamPrepareHeader) X(40, acmStreamReset) \
    X(41, acmStreamSize) X(42, acmStreamUnprepareHeader) X(43, XRegThunkEntry) X(44, DriverProc)

#define PROXY_COUNT 45

#define X(index, name) #name,
static const char *const EXPORT_NAMES[PROXY_COUNT] = { PROXY_EXPORTS(X) };
#undef X

void *g_proxy_targets[PROXY_COUNT];

/* A missing export in the real DLL ends the process with a code naming it, rather than jumping to nothing. */
__attribute__((used)) void __cdecl proxy_resolve(int index)
{
    static HMODULE real;
    void *target;
    if (!real) {
        char path[MAX_PATH];
        UINT length = GetSystemDirectoryA(path, MAX_PATH - 16);
        lstrcpyA(path + length, "\\msacm32.dll");
        real = LoadLibraryA(path);
    }
    target = real ? (void *)GetProcAddress(real, EXPORT_NAMES[index]) : NULL;
    if (!target)
        ExitProcess(0xDEAD0000u | (unsigned)index);
    InterlockedExchangePointer(&g_proxy_targets[index], target);
}

/* Each export: jump if resolved, else resolve with every register kept, then jump. The caller's arguments stay
   untouched on the stack, so this works for any signature. */
#define X(index, name)                                         \
    __asm__(".text\n"                                          \
            ".globl _" #name "\n"                              \
            "_" #name ":\n"                                    \
            "  movl _g_proxy_targets+4*" #index ", %eax\n"     \
            "  testl %eax, %eax\n"                             \
            "  jnz 1f\n"                                       \
            "  pushal\n"                                       \
            "  pushl $" #index "\n"                            \
            "  call _proxy_resolve\n"                          \
            "  addl $4, %esp\n"                                \
            "  popal\n"                                        \
            "  movl _g_proxy_targets+4*" #index ", %eax\n"     \
            "1: jmp *%eax\n"                                   \
            ".section .drectve\n"                              \
            ".ascii \" -export:" #name "\"\n"                  \
            ".text\n");
PROXY_EXPORTS(X)
#undef X
