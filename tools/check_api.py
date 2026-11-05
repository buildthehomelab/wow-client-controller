#!/usr/bin/env python3
"""Every global and method the Lua UI uses must exist in the 3.3.5a client.

    check_api.py <Wow.exe> <folder of extracted FrameXML and GlueXML files>

Global functions come from Wow.exe's script tables (name pointer followed by function pointer); FrameXML's own globals
and frame names from the extracted files. Methods are only checked as strings in the exe, which is weaker: it proves the
client knows the name, not that this object type has it. Stops the build's checks with a list of anything unknown.
"""
import glob
import os
import re
import struct
import subprocess
import sys

LUA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lua")
OURS = {"SLASH_GAMEPAD1"}
LUA_BASE = {
    "pairs", "ipairs", "tostring", "tonumber", "pcall", "type", "unpack", "select", "next", "math", "string", "table",
    "_G", "assert", "error", "print", "date", "time", "strsplit",
}


def bytecode_globals(path):
    listing = subprocess.run(["luajit", "-bl", path], capture_output=True, text=True, check=True).stdout
    return set(re.findall(r'GGET\s+\d+\s+\d+\s+;\s+"([^"]+)"', listing)) | set(
        re.findall(r'GSET\s+\d+\s+\d+\s+;\s+"([^"]+)"', listing))


def methods(path):
    text = re.sub(r"--[^\n]*", "", open(path).read())
    return set(re.findall(r":([A-Za-z_][A-Za-z0-9_]*)\(", text))


def main():
    exe = open(sys.argv[1], "rb").read()
    import_base = 0x400000

    def in_exe_table(name):
        needle = name.encode() + b"\0"
        at = -1
        while True:
            at = exe.find(needle, at + 1)
            if at < 0:
                return False
            if exe[at - 1] == 0:
                return True

    framexml = ""
    for path in glob.glob(os.path.join(sys.argv[2], "*")):
        framexml += open(path, "r", errors="replace").read()

    unknown = []
    for path in sorted(glob.glob(os.path.join(LUA_DIR, "*.lua"))):
        name = os.path.basename(path)
        for symbol in sorted(bytecode_globals(path)):
            if symbol in OURS or symbol in LUA_BASE:
                continue
            if in_exe_table(symbol):
                continue
            if re.search(r"(^|[^A-Za-z0-9_])" + re.escape(symbol) + r"([^A-Za-z0-9_]|$)", framexml):
                continue
            unknown.append((name, "global", symbol))
        for method in sorted(methods(path)):
            if not in_exe_table(method) and method not in ("gmatch",):
                unknown.append((name, "method", method))
    for row in unknown:
        print("UNKNOWN", *row)
    print("%d unknown" % len(unknown))
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
