#!/usr/bin/env python3
"""What the test shell's disk commands should give, from the image.

    h17img.py sum IMAGE              the line SUM d prints
    h17img.py apply IMAGE OUT CMD... the image after FILL/HALF/DIRW,
                                     e.g. FILL:20 HALF:21 DIRW:22
    h17img.py cmp A B                exit 1, listing sectors, if they differ

Records are in CP/M's logical order: host sector n of a track is
physical sector SKEW[n], its two halves the two records.
"""
import sys

SKEW = [0, 4, 8, 2, 6, 1, 5, 9, 3, 7]


def offset(track, rec):
    return (track * 10 + SKEW[rec >> 1]) * 256 + (rec & 1) * 128


def fletcher(disk):
    s1 = s2 = 0
    for track in range(40):
        for rec in range(20):
            off = offset(track, rec)
            for b in disk[off:off + 128]:
                s1 = (s1 + b) & 0xFFFF
                s2 = (s2 + s1) & 0xFFFF
    return f'SUM {s1:04X} {s2:04X}'


def pattern(track, rec, xor):
    return bytes((((rec * 16 + i + track) & 0xFF) ^ xor) for i in range(128))


def apply(disk, cmd):
    name, track = cmd.split(':')
    track = int(track)
    if name == 'FILL':
        recs, data = range(20), lambda r: pattern(track, r, 0)
    elif name == 'HALF':
        recs, data = range(0, 20, 2), lambda r: pattern(track, r, 0x55)
    elif name == 'DIRW':
        recs, data = [5], lambda r: bytes((0xA0 + i) & 0xFF for i in range(128))
    else:
        sys.exit(f'unknown command {name}')
    for rec in recs:
        off = offset(track, rec)
        disk[off:off + 128] = data(rec)


def main():
    cmd = sys.argv[1]
    if cmd == 'sum':
        print(fletcher(open(sys.argv[2], 'rb').read()))
    elif cmd == 'apply':
        disk = bytearray(open(sys.argv[2], 'rb').read())
        for c in sys.argv[4:]:
            apply(disk, c)
        open(sys.argv[3], 'wb').write(disk)
    elif cmd == 'cmp':
        a = open(sys.argv[2], 'rb').read()
        b = open(sys.argv[3], 'rb').read()
        bad = [n for n in range(len(a) // 256)
               if a[n * 256:(n + 1) * 256] != b[n * 256:(n + 1) * 256]]
        if bad:
            print('differ in sectors', ' '.join(map(str, bad)))
            sys.exit(1)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
