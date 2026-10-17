#!/usr/bin/env python3
"""Write HCOS v2 into the reserved tracks of a copy of a Heath CP/M disk.

The reserved tracks (sectors 0-29 of an H17 disk, 7680 bytes) are a memory
image of BIOS-1700H to BIOS+6FFH (src/inc/layout.inc): the boot record in
sector 0, the shell at BIOS-1600H, the BDOS at BIOS-0E00H and the BIOS,
which starts with its cold boot at BIOS-0E0H, at the end of the BDOS's
space, which the BDOS doesn't use.
--base is the BIOS's address: F000 for the H17 build, E800 for H17/H37. Everything
Heath put there is replaced, except the label in bytes 03H-1CH of the
boot record (Heath's H37 BIOS reads it for the disk's format); the rest
of the disk, with its directory and files, is copied as it is. The image
is an H17 .h8d or a single-density H37 .h37 (with its 32-byte geometry
trailer): either way the reserved tracks are its first 7680 bytes.

The boot record's sector ends with the table warm boot checks (SYSTAB in
layout.inc): the length and 16-bit sum of the shell's and the BDOS's code,
from SHSUMB and BDSUMB on.

    mksys.py BASE.h8d OUT.h8d --base BIOS --boot B --shell S --bios B
        [--bdos B]

Each part is a raw image (zmac .cim) assembled at its address.
"""
import argparse
import sys

SYSTAB = 0xF8               # in the boot record's sector
COLD = 0xE0                 # BIOSB - BIOSCB
SUMFROM = {'shell': 0xAA, 'bdos': 0x15}   # SHSUMB, BDSUMB
PARTS = [                    # name, offset from the BIOS, room
    ('boot', -0x1700, SYSTAB),
    ('shell', -0x1600, 0x800),
    ('bdos', -0xE00, 0xE00 - COLD),
    ('bios', -COLD, 0x700 + COLD),  # from its cold boot, BIOSCB
]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('out')
    ap.add_argument('--base', required=True, type=lambda x: int(x, 16))
    for name, _, _ in PARTS:
        ap.add_argument('--' + name, required=name != 'bdos')
    a = ap.parse_args()
    disk = bytearray(open(a.image, 'rb').read())
    if len(disk) not in (102400, 102432):
        sys.exit(f'{a.image}: not a 100K H17 or SS SD H37 image')
    label = disk[3:0x1D]
    image = bytearray(0x1E00)
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
        if name == "bios" and (code[COLD + 3] != 0xC3 or code[COLD + 5] != a.base >> 8):
            sys.exit(f'{path}: not a BIOS built for {a.base:04X}H')
        if len(code) > room:
            sys.exit(f'{path}: {len(code)} bytes, room for {room}')
        off = addr + 0x1700
        image[off:off + len(code)] = code
        print(f'{name}: {len(code)} of {room} bytes')
    image[SYSTAB:SYSTAB + len(table)] = table
    image[3:0x1D] = label
    disk[0:len(image)] = image
    open(a.out, 'wb').write(disk)
    print(f'{a.out}: HCOS v2 in the reserved tracks')


if __name__ == '__main__':
    main()
