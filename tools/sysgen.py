#!/usr/bin/env python3
"""Put HCOS into the system tracks of a Heath CP/M H17 disk image.

The Heath boot loader and BIOS load 44 records from the start of the
disk to D980H: the boot record, the CCP at DA00H (offset 80H) and the
BDOS at E200H (offset 880H), up to EF7FH. HCOS's command processor
(HCCP) and BDOS go in their places, so every cold and warm boot loads
them.

    sysgen.py IMAGE.h8d OUT.h8d --bdos BDOS.bin [--ccp HCCP.bin]

The DRI CCP checks the BDOS's 6-byte serial number, so it is copied
from the BDOS being replaced (HCCP doesn't check it).
"""
import argparse
import sys

LOAD = 0xD980
CCP = 0xDA00
BDOS = 0xE200
END = 0xEF80


def put(disk, addr, end, path, what):
    code = bytearray(open(path, 'rb').read())
    room = end - addr
    if len(code) > room:
        sys.exit(f'{path}: {len(code)} bytes, room for {room}')
    off = addr - LOAD
    size = len(code)
    if what == 'BDOS':
        code[0:6] = disk[off:off + 6]       # serial number
    # Variables after the code are loaded too: start them at zero.
    code += bytes(room - len(code))
    disk[off:off + room] = code
    print(f'{what}: {size} of {room} bytes')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('out')
    ap.add_argument('--bdos', required=True)
    ap.add_argument('--ccp')
    a = ap.parse_args()
    disk = bytearray(open(a.image, 'rb').read())
    if len(disk) != 102400:
        sys.exit(f'{a.image}: not a 100K H17 image')
    if disk[CCP - LOAD] != 0xC3 or disk[CCP - LOAD + 3] != 0xC3:
        sys.exit(f'{a.image}: no CCP at offset {CCP - LOAD:X}H')
    if disk[BDOS - LOAD + 6] != 0xC3:
        sys.exit(f'{a.image}: no BDOS at offset {BDOS - LOAD:X}H')
    put(disk, BDOS, END, a.bdos, 'BDOS')
    if a.ccp:
        put(disk, CCP, BDOS, a.ccp, 'HCCP')
    open(a.out, 'wb').write(disk)
    print(f'{a.out}: HCOS installed')


if __name__ == '__main__':
    main()
