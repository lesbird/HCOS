#!/usr/bin/env python3
"""Write HCOS v2 into the reserved tracks of a copy of a Heath CP/M disk.

The reserved tracks (sectors 0-29 of an H17 disk, 7680 bytes) are a memory
image of D900H-F6FFH (src/inc/layout.inc): the boot record in sector 0,
the shell at DA00H, the BDOS at E200H and the BIOS at F000H. Everything
Heath put there is replaced; the rest of the disk, with its directory and
files, is copied as it is.

The boot record's sector ends with the table warm boot checks (SYSTAB in
layout.inc): the length and 16-bit sum of the shell's and the BDOS's code,
from SHSUMB and BDSUMB on.

    mksys.py BASE.h8d OUT.h8d --boot B --shell S --bios B [--bdos B]

Each part is a raw image (zmac .cim) assembled at its address.
"""
import argparse
import sys

SYSB = 0xD900
SYSEND = 0xF700
SYSTAB = 0xF8               # in the boot record's sector
SUMFROM = {'shell': 0xAA, 'bdos': 0x15}   # SHSUMB, BDSUMB
PARTS = [                    # name, address, room
    ('boot', SYSB, SYSTAB),
    ('shell', 0xDA00, 0x800),
    ('bdos', 0xE200, 0xE00),
    ('bios', 0xF000, SYSEND - 0xF000),
]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('base')
    ap.add_argument('out')
    for name, _, _ in PARTS:
        ap.add_argument('--' + name, required=name != 'bdos')
    a = ap.parse_args()
    disk = bytearray(open(a.base, 'rb').read())
    if len(disk) != 102400:
        sys.exit(f'{a.base}: not a 100K H17 image')
    image = bytearray(SYSEND - SYSB)
    table = b''
    for name, addr, room in PARTS:
        path = getattr(a, name)
        code = open(path, 'rb').read() if path else b''
        if name in SUMFROM:
            part = code[SUMFROM[name]:]
            table += (len(part).to_bytes(2, 'little') +
                      (sum(part) & 0xFFFF).to_bytes(2, 'little'))
        if not path:
            continue
        if len(code) > room:
            sys.exit(f'{path}: {len(code)} bytes, room for {room}')
        off = addr - SYSB
        image[off:off + len(code)] = code
        print(f'{name}: {len(code)} of {room} bytes')
    image[SYSTAB:SYSTAB + len(table)] = table
    disk[0:len(image)] = image
    open(a.out, 'wb').write(disk)
    print(f'{a.out}: HCOS v2 in the reserved tracks')


if __name__ == '__main__':
    main()
