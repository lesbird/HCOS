#!/usr/bin/env python3
"""Put the HCOS BDOS into the system tracks of a Heath CP/M H17 disk image.

The Heath boot loader and BIOS load 44 records from the start of the
disk to D980H: the boot record, the CCP at DA00H (offset 80H) and the
BDOS at E200H (offset 880H), up to EF7FH. The HCOS BDOS replaces the
DRI BDOS there, so every cold and warm boot loads it.

    sysgen.py IMAGE.h8d BDOS.bin [OUT.h8d]

The CCP checks the BDOS's 6-byte serial number, so it is copied from
the BDOS being replaced.
"""
import sys

LOAD = 0xD980
BDOS = 0xE200
END = 0xEF80


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    image, bdos = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) == 4 else image
    disk = bytearray(open(image, 'rb').read())
    code = bytearray(open(bdos, 'rb').read())
    if len(disk) != 102400:
        sys.exit(f'{image}: not a 100K H17 image')
    ccp = 0xDA00 - LOAD
    if disk[ccp] != 0xC3 or disk[ccp + 3] != 0xC3:
        sys.exit(f'{image}: no CCP at offset {ccp:X}H')
    off = BDOS - LOAD
    if disk[off + 6] != 0xC3:
        sys.exit(f'{image}: no BDOS at offset {off:X}H')
    size = len(code)
    if size > END - BDOS:
        sys.exit(f'{bdos}: {len(code)} bytes, room for {END - BDOS}')
    code[0:6] = disk[off:off + 6]           # serial number
    # The variables after the code are loaded too: start them at zero.
    code += bytes(END - BDOS - len(code))
    disk[off:off + len(code)] = code
    open(out, 'wb').write(disk)
    print(f'{out}: HCOS BDOS installed, {size} of {END - BDOS} bytes')


if __name__ == '__main__':
    main()
