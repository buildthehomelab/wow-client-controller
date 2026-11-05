#!/bin/sh
# Builds out/msacm32.dll (32-bit Windows) from any machine with Zig. Usage: ZIG=/path/to/zig ./build.sh
set -eu
cd "$(dirname "$0")"
ZIG="${ZIG:-zig}"
LUAC="${LUAC:-luac}"
mkdir -p out

"$LUAC" -p lua/*.lua

# The compiler's cache can't see the files .incbin pulls in, so their hash goes on the command line. Without it an
# edit to a Lua file can build a DLL holding the old copy.
STAMP=$(cat lua/*.lua art/*.blp | shasum -a 256 | cut -c1-16)

# -nostdlib also drops the Windows headers, so they're named by hand.
ZIG_LIB=$("$ZIG" env | sed -n 's/.*lib_dir = "\(.*\)".*/\1/p')

"$ZIG" cc -target x86-windows-gnu -shared -O2 -g0 -s -nostdlib -fno-builtin \
    -isystem "$ZIG_LIB/libc/include/any-windows-any" -D_WIN32_WINNT=0x0601 \
    -std=c11 -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type \
    -fno-stack-protector -DEMBED_STAMP="$STAMP" \
    -Ithird_party/include -Isrc \
    src/main.c src/pad.c src/log.c src/logic.c src/proxy.c src/nocrt.c \
    -Wl,-e,DllMain@12 -luser32 -lkernel32 \
    -o out/msacm32.dll

rm -f out/*.lib out/*.pdb
cp third_party/SDL3.dll out/SDL3.dll

python3 tools/check_dll.py out/msacm32.dll

shasum -a 256 out/msacm32.dll out/SDL3.dll
