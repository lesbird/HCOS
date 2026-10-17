# Formatting H17 disks (for HCOS FORMAT)

Research for the HCOS v2 FORMAT program: hard-sectored H17 disks, 40 tracks
× 10 × 256, single-sided, for CP/M and for HDOS. It builds on `h17.md`
(ports, checksum, timing). The scratch files are in
`.../scratchpad/fmt17/`: `fmt.dis` (FORMAT.COM), `rom.dis` (444-19),
`hd/sy.dis` (HDOS 2.0 SY.DVD) and `asmx/` (the HDOS 3.0 sources).

Sources:

- Heath CP/M 2.2.03 `FORMAT.COM`, "Format Version 2.03", 5760 bytes, from
  `H89/disks/CPM_2-2-03.H8D`. Disassembled at 0100H.
- HDOS 2.0 `SY.DVD` and `INIT.ABS` from `H89/disks/HDOS_2-0_System.h8d`.
  In SY.DVD, after the 8-byte header, the INIT block runs at
  file offset + 1D82H. That offset was found from a loop target
  (`JP 2501H` loops back to offset 077FH).
- HDOS 3.0 `testHdos/source/init.h8a` (asmx).
- The H17 ROM 444-19.
- The emulator's `core/devices/H17.cpp` and `core/media/H17Disk.*`.
- Emulator runs with `h89run`: CP/M FORMAT on a blank image in drive B.

T-states are Z80 T at 2.048 MHz. One byte is 128 T, one sector slot is
40,960 T (320 bytes, 20 ms), and one turn is 409,600 T.

## 1. Heath CP/M 2.2.03 FORMAT.COM (the H17 path, 0445H-0548H)

### 1.1 What it calls

FORMAT drives ports 7CH-7FH itself. It uses the BIOS only to find things:

| Use | How |
|---|---|
| SELDSK | `LHLD 0001H` + 18H = F01BH, with E=1 (no login) → DPH (0640H, 06DCH) |
| Controller type | DPH+10H (extension byte 0): AND E0H = 40H means H17 (0395H). 80H means H37, which takes another path. The bits AND 09H must be 0 |
| Drive-select bit | DPH+11H → 171EH. The 7FH shadow is kept privately at 171BH |
| "one drive as two" | DPH+16H bit 1 set → "This drive not available" |
| BIOS timers | `LHLD 0009H` (the RST 1 JMP target, F821H) − 3 = **F81EH**. It zeroes F81EH/F81FH (motor-off and deselect, so the ISR won't stop the motor) and uses F820H (the 4 ms down-counter) for the spin-up and settle waits |
| Tick counter | 000BH (the 2 ms tick) for every millisecond wait and for the hole timing |

The track count is 1719H = 28H (40). It does not write a system to tracks
0-2, and there is no SYSGEN step.

### 1.2 Sequence

| Step | Code | What it does |
|---|---|---|
| WP + restore | 06E6H | DI, timers F81E/F81F := 0, EI. Shadow := select\|MO (10H), OUT 7FH. If 7FH bit 2 (WP) → "write protected". Step out until T0 (`0738H`: DI=0, pulse ST, wait 15 ticks = 30 ms). F820H := max(6, …), then wait for F820H = 0 (24 ms) |
| Spin-up | 0467H | B=track=0, C=sector=0, EI, motor on, F820H := FAH (1 s), wait |
| Speed check | 0549H | Count hole edges for 1000 ticks (2 s). It needs 208-230 (the nominal is 10 turns × 22 = 220). Otherwise "Wrong type of media…" |
| **Track loop** | 0492H | Wait 23H ticks (**70 ms settle**) |
| Media test | 058EH | Skipped if FCB1 starts with `F` or the tail is ` *` (flag 170EH). See 1.4 |
| Fill char | 04ADH | `OUT 7DH,00H` |
| **Erase** | 04B0H | Write gate **on** (shadow+1), then wait 7DH ticks (**250 ms**, more than a turn). The USRT sends the fill char 00H. The gate stays on until the end of sector 0 |
| Find index | 04BCH | 0757H (wait for the hole to end, +20 loops), 0764H (wait for a hole edge, +20 loops). Then `0627H` measures, in ticks, from the current hole to the next hole edge. Loop until an interval is ≥ 6 ticks (a normal sector), then loop until one is < 6 (S9→index, 10 ms). We are now at the index hole |
| Sync to S0 | 04D5H | 0757H: wait for the index hole to end, +20 loops (280 T). **DI** |
| **Sector loop** | 04DAH | For C = 0..9: 0764H waits for a hole's leading edge and 20 loops (280 T), then writes the sector (1.3), then **gate off** (`OUT 7FH,shadow`) |
| Next track | 0524H | **EI**, C=0, B+1. If B=40, done. Delay 84H loops (132 × 14 = 1848 T, **0.9 ms**, H17SDL). Step in (DI bit 20H, pulse, wait 15 ticks = 30 ms), back to the track loop |
| End | 0539H | Restore to track 0, motor and select off. **No read-back verify** |

The time per track is about 70 + 250 + (200-400 index search) + 200 + 30
ms, about 0.9 s. The whole disk takes about 40 s (the emulator run
finished within 90 s of emulated time).

### 1.3 Per-sector bytes (every track the same, tracks 0-2 included)

The gate goes on (or, for S0, is already on) at about 400 T after the
hole's leading edge, about byte 3. The table counts bytes from the gate.

| Gate byte | Content | Written by |
|---|---|---|
| 0-9 | 10 × 00H | `076FH` = R.WSP copy (delay 1, gate on, C=10 zeros) |
| 10 | FDH header sync (checksum reset: D := 0) | `0781H` |
| 11 | volume **00H** (`XOR A`) | WNB 0784H |
| 12 | track (B) | |
| 13 | sector (C, 0-9) | |
| 14 | header checksum (D) | |
| 15 | 00H | |
| 16-25 | 10 × 00H | WSP again (the gate is already on) |
| 26 | FDH data sync, D := 0 | |
| 27-282 | 256 × **E5H** | |
| 283 | data checksum | |
| 284-285 | 00H, 00H (WNB returns the new checksum, which is 0) | so the checksum leaves the shift register |
| — | gate off, at about slot byte 288 (about 32 bytes, 4100 T, before the next hole) | |

Counted from the hole: header sync at about byte 13, data sync at about
29, end at about 289, out of 320. This is **computed from the code, not
measured** on real hardware **[UNVERIFIED]**. A per-byte WNB call costs
about 104 T plus the TBE poll. DI covers the whole 10-sector track
(about 200 ms of lost ticks).

**Volume is 0 on all 40 tracks. The fill is E5H.** The reserved tracks
get the same treatment.

### 1.4 The media test (058EH) and the emulator

For each pattern 00H, 55H, FFH, the media test:

1. writes a hole-synced R.WSP preamble (10 zeros + FDH) and then 3122
   pattern bytes, nearly a whole turn;
2. waits for the next hole, delays 48 loops and arms sync;
3. compares 3120 bytes.

That works on real media, where the FDH it just wrote is the next sync
mark. **In the emulator it always fails with "Media error."** (seen with
`h89run`). The emulator's sync search only finds its synthesized marks at
slot bytes 10 and 25.

`FORMAT *` (or a first argument starting with `F`) skips the test.
Formatting a blank image in B: that way gave all 400 sectors = E5H.

## 2. The HDOS side

### 2.1 The H17 ROM (444-19): there is no format routine

R.SYDD (1BCEH) dispatches as follows:

| Function | Goes to |
|---|---|
| 0 | READ |
| 1 | WRITE |
| 2 | READR |
| 3, 4 | R.XOK (no-op) |
| 5 | ABORT |
| > 5 | MOUNT |

R.WRITE writes only a data block (`h17.md` 3.4), and none of the 18
vectors at 2058H-2090H writes headers.

The ROM does have an unvectored routine at 1FB2H that looks like a test:

1. It selects 19H (MO+DS2+WG).
2. It writes R.WSP and then 0C5CH bytes of 47H.
3. It turns the gate off and reads back 0C5AH bytes.
4. It HALTs.

It writes no headers. Its purpose is **[UNVERIFIED]**.

### 2.2 HDOS INIT: the format is in the SY driver

**HDOS 3.0 INIT** (`init.h8a`):

- IDS calls `SUBFUN INI.IDS`. That is the device driver's INIT
  sub-function, at DVT.PAR + SB.SDB−SB.BOO.
- Then it writes a dummy boot to sector 0 with volume 0.
- The SY driver source isn't in asmx.
- INIT does **no** read-back. GBL asks the user to type in the bad
  sector numbers (from TEST17).

**HDOS 2.0 SY.DVD** does contain the format code, at offsets 0726H-07BFH
(running at 24A8H-2541H). It uses the ROM's R.WSP (via 2094H) and R.WNB
(via 2097H). It is **the same algorithm as CP/M FORMAT, which was
evidently derived from it**: the 250 ms erase with the gate on, the
interval-based index search (0842H), DI per track, gate off after each
sector, 0.84 ms and then a step, and the identical 1000-tick speed check
(07D6H). The differences:

| | HDOS 2.0 SY.DVD | CP/M FORMAT |
|---|---|---|
| Header volume | `MVI A,nn` at 075FH, with the operand (24E2H) patched. It is 0 for track 0 (`XRA A / STA` at 072AH). After each track, `CALL 2C24H` / `STA 24E2H` sets it, presumably to the new serial **[UNVERIFIED: 2C24H is in the resident part]** | 0 everywhere |
| Data fill | 128 × "GL" (47H, 4CH) | 256 × E5H |
| Delay before step | 7BH loops (1722 T) | 84H loops (1848 T) |
| Media test | none | 00/55/FF |

Everything else in the sector is identical (10×00, FD, vol, trk, sec,
cks, 00, 10×00, FD, 256 data, cks, 00, 00).

So **HDOS = volume 0 on track 0 and the label serial on tracks 1-39**, as
stated. That matters because the ROM's R.LPS compares the volume. The
label (T0 S9), boot, RGT, GRT and directory are written afterwards by
INIT through ordinary writes, and are outside the format layer.

## 3. What the emulator accepts

At the gate's rising edge it clears the buffer, records `writeStart_` and
stops any sync search. OUT 7CH appends to the buffer only while the gate
is on, and TBE paces the writes at 128 T per byte. At the falling edge,
`commitWrite()` scans the buffer:

| Rule | Detail |
|---|---|
| Sync | Scan for the next FDH. Gap bytes may be anything except FDH |
| Header | It is a header if the 4 bytes after the FDH are vol, trk, sec, cks with **trk = the head's current track**, **sec < 10**, and **cks = the checksum of the 3 bytes**. The volume can be anything. Then: sector := sec, and the **track's** volume override := vol. It is one value per track, and the last header wins |
| Data | The next FDH is followed by 256 bytes → written to `sector`. The data checksum and the trailing bytes are **not checked**. If no header came before it in this gate period, `sector` is the slot that the gate rose in (`writeStart_`) |
| Not checked | where in the slot the write started (when a header is present), gap lengths, the volume, the order of sectors, the index |
| Several records per gate | allowed: header/data pairs repeat within one gate period |
| Erase with no bytes | no-op |
| Read-back | The track stream is regenerated from the image: header sync at slot byte 10, data at 25, volume = override, else the label serial (tracks ≥ 1 with an HDOS label), else 0 |
| Persistence | Data goes through to the .h8d. **Volume overrides live only in memory and in the saved state, not in the .h8d.** After a reload the volume comes back from the label. So an HDOS-formatted disk needs a valid label (bytes 0CH = 400 sectors, 0EH = 256) with the same serial |

**Pitfalls:**

- A header with the wrong track byte is treated as data. The 256 bytes
  after that FDH overwrite the slot's sector.
- `FD 00 00 00 00` on track 0 parses as a valid header. This is why the
  00H media-test pass changes nothing.
- A blank image already has synthesized headers everywhere. So in the
  emulator, a header check cannot tell whether a format failed. **Verify
  the data fill instead.**

**Minimal sequence the emulator accepts**: `FD vol trk sec cks FD
<256 bytes>`.

**Recommended sequence (Heath's, and accepted)**: per sector, gate on
about 400 T after the hole edge, then

`10×00, FD, vol, trk, sec, cks, 00, 10×00, FD, 256×fill, dcks, 00, 00`,
then gate off. That is 286 bytes, about 36,600 T.

## 4. Recommended HCOS H17 format routine (8080)

Use the driver's existing primitives: WNB, a WSP-like "C zeros + FDH,
D := 0", the hole edge and hole end waits with the 20-loop (280 T) delay,
step and restore, select and motor.

```
FMT17(drive, vol, fill):          ; vol: 0 for CP/M; HDOS serial (T0 gets 0)
  select+motor, stop the auto-off timers; WP (7FH bit 2) -> error
  restore to T0; spin-up 1 s (if the motor was off)
  [optional ready check: holes seen within 2 turns]
  OUT 7DH,00H                     ; fill char
  for T = 0..39:
    settle 70 ms (Heath)          ; ticks, EI
    hv := (T=0) ? 0 : vol
    gate ON; wait 250 ms          ; erase, EI (Heath)
    FINDIDX: wait for a hole edge; repeat: measure hole->next hole edge
             until >= 6 ticks (or > ~15 ms of loop time); then until < 6:
             now at the index hole.  Wait for it to end, +280 T
    for S = 0..9:
      DI; wait for a hole edge, +280 T  ; gate on here (already on for S=0)
      WSP(10): 10×00, FD, D:=0
      WNB hv, T, S, D; WNB 00
      WSP(10); 256 × WNB fill; WNB D; WNB 00; WNB 00
      gate OFF; EI                ; EI in the ~4000 T gap keeps the clock going
    if T<39: delay ~0.9 ms (1850 T); step in; wait 30 ms
  restore to T0, mark the track known, re-arm the motor-off timer
```

**Timing budget:**

| Point | Budget |
|---|---|
| Hole edge → gate on | ~400 T (byte 3), so the header sync falls at about byte 13. The ROM and the BIOS search for up to about 26 bytes from where they arm (bytes 3-8.5), so anything from byte 5 to byte 20 is safe |
| Per-byte loop | `MVI/CALL WNB/DCR/JNZ` with WNB (`MOV E,A / IN 7DH / ANA A / JP P / MOV A,E / OUT 7CH / XRA D / RLC / MOV D,A / RET`) is about 104 T plus polling, under 128 T. An ISR inside a sector would break this, so DI from the hole wait to gate off |
| End of sector → next hole | about 30 bytes (≥ 3800 T). Gate off, EI and the next hole-edge wait fit easily |
| Index search | Do it with the gate on (the erase continues). 10 ms intervals measure 4-5 ticks and 20 ms intervals 9-10, so a threshold of 6 ticks (12 ms) is robust |

**Verify (recommended, Heath does none)**, after the track is written, or
in a second pass over the disk:

1. Find the index again as above. Then, for S = 0..9, with DI: wait for
   the hole edge + 280 T.
2. Arm the sync (`OUT 7EH,FDH / IN 7EH`) and poll bit 3 (≤ 80 polls).
3. Read vol/trk/sec/cks. Require trk = T and sec = S, the checksum, and
   vol = hv.
4. Arm the sync and read 256 bytes, each = fill, plus the data checksum.
5. EI.

That is one turn (200 ms) per track. As a simpler alternative, call the
driver's sector read for S = 0..9 in the XLT order and compare against the
fill. It costs more turns, but it is the same code that will read the
disk.

**The emulator only proves the data check**, because headers are always
synthesized. On error, re-format that track once, then report "bad
track" (HDOS: let INIT mark bad sectors; CP/M: no bad-sector map, so
fail).

**What to write per OS:**

- **CP/M**: vol 0 on every track, E5H fill. The E5H directory is already
  empty. SYSGEN writes tracks 0-2 later.
- **HDOS**: vol 0 on track 0 and the serial on tracks 1-39. The fill is
  arbitrary: Heath uses "GL", and E5H is fine. Then an INIT-equivalent
  must write the boot, the label (T0 S9: byte 0 = serial, 0CH = 400,
  0EH = 256), RGT, GRT and DIRECT.SYS **[UNVERIFIED: layout, see
  init.h8a FOV/IDD]**.
