#!/usr/bin/env python3
"""fill.py IMAGE [BYTE] [SKIP...] - exit 1 unless every 256-byte sector of
the image (its first 102400 bytes) is BYTE (default E5), apart from the
sector numbers in SKIP; and make a blank (zeroed) copy: fill.py --blank
IN OUT keeps IN's trailer (an .h37 geometry trailer)."""
import sys

if sys.argv[1] == '--blank':
    d = open(sys.argv[2], 'rb').read()
    open(sys.argv[3], 'wb').write(bytes(102400) + d[102400:])
    sys.exit(0)
d = open(sys.argv[1], 'rb').read()
want = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0xE5
skip = {int(x) for x in sys.argv[3:]}
bad = [n for n in range(400) if n not in skip and d[n * 256:(n + 1) * 256] != bytes([want]) * 256]
if bad:
    print('not filled:', bad[:20])
    sys.exit(1)
