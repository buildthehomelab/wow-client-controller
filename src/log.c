#include "log.h"

#include <windows.h>
#include <stdarg.h>

static HANDLE g_log = INVALID_HANDLE_VALUE;

void log_open(const char *game_directory)
{
    char path[MAX_PATH + 32];
    wsprintfA(path, "%s\\Logs", game_directory);
    CreateDirectoryA(path, NULL);
    wsprintfA(path, "%s\\Logs\\Controller.log", game_directory);
    g_log = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

void log_line(const char *format, ...)
{
    char line[1100]; /* wvsprintfA writes at most 1024 */
    int length;
    DWORD written;
    va_list args;
    if (g_log == INVALID_HANDLE_VALUE)
        return;
    va_start(args, format);
    length = wvsprintfA(line, format, args);
    va_end(args);
    if (length < 0)
        return;
    line[length++] = '\r';
    line[length++] = '\n';
    WriteFile(g_log, line, (DWORD)length, &written, NULL);
}
