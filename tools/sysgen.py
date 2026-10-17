#!/usr/bin/env python3
"""Put HCOS into the system tracks of a Heath CP/M disk image.

The Heath boot loader and BIOS load 44 records from the system tracks:
the CCP, then the BDOS 800H after it, up to 80H before the BIOS. HCOS's
command processor (HCCP) and BDOS go in their places, so every cold and
warm boot loads them. Works for H17 images (.h8d) and single-density
H37 images (.h37, with their geometry trailer); the system track layout
differs between them, so the CCP is found by DRI's copyright line.

    sysgen.py IMAGE OUT --base CCPB --bdos BDOS.bin [--ccp HCCP.bin]

--base is where the kernel was built to run (CCPB, e.g. DA00); it must
match the CCP being replaced. The DRI CCP checks the BDOS's 6-byte
serial number, so that is copied from the BDOS being replaced.

The Heath BIOS's sign-on (in BIOS.SYS) is changed to name HCOS, in
place and at the same length.
"""
import argparse
import sys

CCPLEN = 0x800
BDOSLEN = 0xD80              # BDOS up to 80H below the BIOS
SIGNON = b'HEATH/ZENITH CP/M 2.2X03  09/17/81'
HCOSON = b'HCOS ON HEATH/ZENITH CP/M 2.2X03  '
assert len(SIGNON) == len(HCOSON)


def put(disk, off, room, path, what, serial=False):
    code = bytearray(open(path, 'rb').read())
    if len(code) > room:
        sys.exit(f'{path}: {len(code)} bytes, room for {room}')
    size = len(code)
    if serial:
        code[0:6] = disk[off:off + 6]
    code += bytes(room - len(code))    # variables after the code: zero
    disk[off:off + room] = code
    print(f'{what}: {size} of {room} bytes')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('out')
    ap.add_argument('--base', required=True, type=lambda x: int(x, 16))
    ap.add_argument('--bdos', required=True)
    ap.add_argument('--ccp')
    a = ap.parse_args()
    disk = bytearray(open(a.image, 'rb').read())
    if len(disk) < 102400:
        sys.exit(f'{a.image}: not a 100K H17 or H37 image')
    i = disk.find(b'COPYRIGHT (C) 1979, DIGITAL RESEARCH')
    if i < 0:
        sys.exit(f'{a.image}: no CP/M CCP in the system tracks')
    ccp = i - 0x18
    if disk[ccp] != 0xC3:
        sys.exit(f'{a.image}: no CCP entry at offset {ccp:X}H')
    base = (disk[ccp + 1] | disk[ccp + 2] << 8) - 0x35C
    if base != a.base:
        sys.exit(f'{a.image}: its CCP is at {base:04X}H, the kernel was '
                 f'built for {a.base:04X}H')
    bdos = ccp + CCPLEN
    if disk[bdos + 6] != 0xC3:
        sys.exit(f'{a.image}: no BDOS at offset {bdos:X}H')
    put(disk, bdos, BDOSLEN, a.bdos, 'BDOS', serial=True)
    if a.ccp:
        put(disk, ccp, CCPLEN, a.ccp, 'HCCP')
    n = disk.count(SIGNON)
    if n == 1:
        i = disk.find(SIGNON)
        disk[i:i + len(SIGNON)] = HCOSON
        print('BIOS sign-on: ' + HCOSON.decode().rstrip())
    else:
        print(f'BIOS sign-on: {n} copies of the Heath sign-on, not changed')
    open(a.out, 'wb').write(disk)
    print(f'{a.out}: HCOS installed (CCP at {base:04X}H)')


if __name__ == '__main__':
    main()
