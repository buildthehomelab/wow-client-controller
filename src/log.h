/* Logs\Controller.log, rewritten each time the game starts: the first thing to ask for when something fails. */
#ifndef LOG_H
#define LOG_H

void log_open(const char *game_directory);
void log_line(const char *format, ...) __attribute__((format(printf, 1, 2)));

#endif
