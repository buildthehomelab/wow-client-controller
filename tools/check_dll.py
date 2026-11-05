#!/usr/bin/env python3
"""After a build: every embedded file is the current copy, and the DLL imports only what every Windows has. Wow.exe imports
this DLL directly, so anything else it depends on could stop the game starting. Reads the PE by hand: no dependencies.
"""
import glob
import struct
import sys

ALLOWED = {"KERNEL32.DLL", "USER32.DLL"}


def imports(data):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    sections = struct.unpack_from("<H", data, pe + 6)[0]
    optional = struct.unpack_from("<H", data, pe + 20)[0]
    table = pe + 24 + optional
    rows = [struct.unpack_from("<III", data, table + i * 40 + 8) for i in range(sections)]

    def to_file(rva):
        for size, virtual, raw_size in [(r[0], r[1], r[2]) for r in rows]:
            if virtual <= rva < virtual + max(size, raw_size):
                offset = struct.unpack_from("<I", data, table + rows.index((size, virtual, raw_size)) * 40 + 20)[0]
                return rva - virtual + offset
        raise SystemExit("bad address in the import table")

    directory = struct.unpack_from("<I", data, pe + 24 + 104)[0]
    names = []
    at = to_file(directory)
    while True:
        name_rva = struct.unpack_from("<I", data, at + 12)[0]
        if name_rva == 0:
            return names
        start = to_file(name_rva)
        names.append(data[start:data.index(b"\0", start)].decode())
        at += 20


def main():
    dll = open(sys.argv[1], "rb").read()
    for path in sorted(glob.glob("lua/*.lua") + glob.glob("art/*.blp")):
        if open(path, "rb").read() not in dll:
            raise SystemExit(sys.argv[1] + " does not hold the current " + path)
    found = imports(dll)
    extra = [name for name in found if name.upper() not in ALLOWED]
    if extra:
        raise SystemExit(sys.argv[1] + " imports " + ", ".join(extra))
    print("embedded files current; imports", ", ".join(found))


if __name__ == "__main__":
    main()
