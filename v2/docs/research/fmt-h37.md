# Formatting H37 disks (WD1797 Write Track)

Research for the HCOS v2 FORMAT program. Read [h37.md](h37.md) first for
the ports, latches, the HALT/DRQ loop and the label.

**Sources.** Heath `FORMAT.COM` 2.03 from
`H89/disks/CPM-2-2-03-64K-H17-H37-BOOT_00A3A2A6.H37`, disassembled
(H37 part 0849H-0B79H). An `h89run --trace-io` run of it formatting a
blank ImageDisk in DK1 (the 3125-byte stream captured from the trace, and
the resulting `.imd` decoded). The emulator's `core/devices/H37.cpp` and
`core/media/SoftDisk.*`. From the HDOS H37 disk
(`HDOS-2-H37IMGR-AND-H8DIMGR3_0096EA5B.H37`): `SDUP37.ABS`, `DK.DVD` and
the label.

## 1. Heath FORMAT 2.03, H37

### The Write Track stream, SS SD 10 x 256 (format 0)

FORMAT builds the whole track in memory from a run-length template
(count, value pairs; templates at 0AF0H FM, 0B16H MFM 16 x 256,
0B42H MFM 5 x 1024). This is the stream it sent for track 0, taken from
the trace:

| Part | Bytes | Notes |
|---|---|---|
| gap 4a (after index) | 16 x FFH | no index mark (no FCH), no sync zeros before it |
| sync | 6 x 00H | |
| IDAM | FEH | |
| C H R N | track, side (0/1), sector, 01H | written per track over the template's 00 00 00 |
| ID CRC | F7H | the 1797 writes 2 CRC bytes |
| gap 2 | 11 x FFH | |
| sync | 6 x 00H | |
| DAM | FBH | |
| data | 256 x E5H | |
| data CRC | F7H | |
| gap 3 | 16 x FFH | |
| (repeat sync..gap 3 for the other 9 sectors) | 303 bytes per sector | |
| gap 4b | 24 x FFH, then 128 x FFH of slack | the 1797 stops at the next index |

Buffer: 16 + 10 x 303 = 3046 bytes, then 152 FFH, 3198 bytes in all.
On the disk each F7H becomes 2 bytes, so a sector is 304 disk bytes and
the formatted part is 3056 of the nominal 3125 (300 rpm, 125 kbit/s).

**Interleave 3, the same on every track (no track skew).** Heath's
routine (127BH) places sector d at slot c, then c += 3 (mod n), moving
on past used slots. Physical order:

| Sectors | Order of the IDs from the index |
|---|---|
| 10 (FM) | 1 8 5 2 9 6 3 10 7 4 |
| 16 (MFM) | 1 12 7 2 13 8 3 14 9 4 15 10 5 16 11 6 |
| 5 (1024) | 1 3 5 2 4 |

The `.imd` result has `1 8 5 2 9 6 3 10 7 4` on every cylinder, with
C = cylinder, H = 0 and N = 1.

**Speed check.** When the INTRQ arrives FORMAT compares the byte pointer
with two limits. The pointer must be at least 3070 bytes into the buffer
(16 + 3030 + 24) and less than 3198. Otherwise the track fails. With F7H
doubled that allows about 291-303 rpm. The emulator takes exactly 3125
stream bytes (it doesn't double the F7H), which is inside these limits.

### Feeding it, stepping, verifying

All of this is the H37 part of FORMAT (0849H-0A1FH):

1. Clear the BIOS motor and deselect timers (0023H/0024H) and the latch
   copy (0025H). Write 0 to 79H. Set the latch to drive select + density
   (04H for MFM) + 09H (motor + INTRQ enable).
2. Wait 3 x 256 ticks, about 1.5 s, on the high byte of the tick counter
   at 000CH. Send Force Interrupt D0H. Count changes of status bit 1
   (index) over 200 ticks (400 ms). It needs 2-6 of them, otherwise
   "Wrong type of media...".
3. Build the buffer and the interleave table. Send Restore **03H** (no
   head load, no verify, 30 ms). Status bit 2 (track 0) must be set.
4. For each track, then side:
   - Patch every ID: C = track, H = side, R = from the table.
   - Set latch DRQ enable (02H).
   - Store the completion address in 0026H, set DE = buffer, HL = loop,
     and send **F4H** (Write Track, E = 15/30 ms settle), or F6H for side 1.
   - The loop (byte fetched before the HALT):
     ```
     LOOP: ldax d ! hlt ! out 7Bh ! inx d ! pchl
     ```
   - The BIOS's RST 4 handler reads the status and jumps to the
     completion address with the status in A. **Any nonzero status
     fails** (write protect 40H, lost data 04H, not ready 80H). DRQ
     enable is turned off, then the speed check above.
   - Wait 2 ticks (4 ms). On a two-sided disk do side 1 next. Otherwise
     send Step In **5BH** (update the track register, head load,
     30 ms, no verify).
5. When every track is done: write 0 to 79H, set the data register to
   tracks - 11 (29 or 69) and send Seek **1FH** with verify. A seek error
   (10H) fails; this is the only check that an ID can be read back. Then
   Restore 03H, and track 0 must be set.
6. Write the label (below) with Write Sector **ACH** (E delay) to
   sector 1 of the track under the head (track 0, side 0), from a
   1024-byte buffer, through the same kind of HALT loop.

**There is no Read Sector verify pass** (the trace has no 88H to the
formatted drive). **The directory isn't written separately:** every data
field was written as E5H by Write Track, so the directory is already
empty. Only T0S1 is written again.

FORMAT relies on the BIOS's RST 4 handler and on its fixed page-zero
cells (0023H-0026H). A program for HCOS can't do that, because
HCOS's are private (section 4).

### The label, T0S1

The 1024-byte buffer is filled with E5H, then:

| Byte | Value | Source |
|---|---|---|
| 00-03 | E5 | not written (the boot disk's `JMP` and 60H come from SYSGEN, not FORMAT) |
| 04 | 00 | |
| 05 | (ext0 AND E8H) OR table flags | controller bits 7-5 and the 96-tpi bit 3 of the drive's DPH extension; flags bit 0 DS, bit 1 DD, bit 2 1024 |
| 06 | E5 | not written |
| 07 | records per sector (02) | table |
| 08 | records per block (08) | table |
| 09-0A | E5 | not written |
| 0B | (ext6 AND FEH) OR TPI (0 = 48, 1 = 96) | |
| 0C | E5 | not written |
| 0D-1B | DPB, 15 bytes | table (h37.md section 3) |
| 1C | CPL(sum of 04H-1BH) | so sum(04H-1CH) + 1 = 0 |
| 1D-FF | E5 | |

The format number is 0-11: +6 for a 96-tpi drive (ext0 bit 3), +2 for
DD, +2 more for 1024-byte sectors, +1 for two sides. The table entry is
at 0B7AH + 19 x number.

From the run (DK1 is a 96-tpi drive in this BIOS, so it got format 6, 80
tracks):
`.. .. .. .. 00 68 E5 02 08 E5 E5 01 E5 14 00 03 07 00 BF 00 3F 00 C0 00 10 00 03 00 09`.
For format 0 on a 48-tpi drive whose ext0 is 62H it would be
`00 60 E5 02 08 E5 E5 00 E5 14 00 03 07 00 5B 00 3F 00 C0 00 10 00 03 00 76`
[computed, not run: FORMAT refused DK2 here, "not available in current
configuration"].

### The other formats, for later

| | MFM 16 x 256 (template 0B16H) | MFM 5 x 1024 (0B42H) |
|---|---|---|
| gap 4a | 32 x 4EH | 32 x 4EH |
| per sector | 12 x 00, 3 x F5, FE, C H R, 01, F7, 22 x 4E, 12 x 00, 3 x F5, FB, 256 x E5, F7, **54 x 4E** = 370 | the same, N = 03, 1024 x E5, **98 x 4E** = 1182 |
| gap 4b | 24 x 4E, then 429 slack | 24 x 4E, then 461 slack |
| limits | 5976 to 6405 bytes | 5966 to 6427 |

- Latch bit 2 is set for the whole disk, track 0 included.
- **Two-sided:** each cylinder is done side 0 (F4H, H = 0) and then
  side 1 (F6H, H = 1) before the step. C is the cylinder on both sides.
- **96 tpi:** 80 tracks.
- There is no IAM (C2/FC) on any format.

## 2. The emulator's Write Track

`H37::command`, `process` (WriteTrackWait/WriteTrack) and
`commitWriteTrack`:

| Stage | What happens |
|---|---|
| command F0H-FFH | busy; U bit 1 = side; **DRQ set at once**. The start is now + 30 ms if E (04H). It waits for the first index after start + 3 byte times. No disk / motor off: never finishes (eventTime = max), so a ready check is needed first |
| at the index | write protect: finish with 40H. **DRQ still set (first byte not written): finish with lost data 04H.** Otherwise the first byte is taken |
| each byte | every `kRevolutionCycles / 3125` = 131 cycles (FM, 64 µs) or 65 (MFM). A byte that didn't come is recorded as 00H and sets lost data, and the command goes on |
| end | after exactly **3125 (FM) / 6250 (MFM) stream bytes**; F7H counts as one. Then commit, then INTRQ with status 0 (or 04H) |

`commitWriteTrack` parses the bytes:

- Look for **FEH**. The next 4 bytes are C H R N. Nothing checks the ID
  CRC byte, N or the gaps.
- Then look for the first **F8H-FBH** before the next FEH. FBH is normal
  and F8H-FAH are deleted. If an FEH comes first, the sector has no
  data, and Read Sector can never find it.
- Data = the bytes after the mark up to the first **F7H**. Their count
  isn't checked against N.
- F5H, F6H, FCH, the sync zeros and the gap fill are ignored. Density =
  the latch MFM bit (Read Sector later needs the same density).
- The sector positions in the stream are not kept. The emulator spaces
  the sectors evenly around the track (40/80-byte gap, then
  (3125-40)/n apart) in stream order, so **the interleave in the stream's
  order is kept and timed**.

Gotchas: never use **FEH, F8H-FBH or F7H as a fill byte**, and no data
byte can be F7H in a format pattern (E5H, FFH, 4EH and 00H are safe).
Each FEH makes a sector, even one in a gap.

**Storage.** `.imd` keeps everything: R order, C/H maps, N, density,
fill (compressed). Raw **`.h37`** keeps only the data, by R = 1..SPT for
each cylinder/side, plus the trailer `SPT=10 SSZ=0256 TRK=40 SID=1 FM`.
A track is saved only if all of these hold:

- the sectors are numbered **1..n**;
- every sector is the same size;
- every track has the same count and density.

Until every track has the new geometry, the change stays in memory (the
trailer is rewritten when it does). Formatting past the last cylinder
or onto side 1 grows the image. Interleave, C and H are lost: on reload
they are rebuilt as C = cylinder, H = side, R = 1..n in order. **Use
`.imd` disks to test FORMAT** (a blank one is 40 x
`02 cc 00 0A 01 01..0A` + 10 x `02 00`, after the
`IMD ...\r\n` + 1AH header).

**The minimal stream the emulator accepts** is just
`FE C H R N  FB <data>  F7`, repeated, padded to 3125 bytes. Use Heath's
stream above instead. The real 1797 needs it (sync zeros before each
mark, gap 2 of at least 11 bytes for the write splice, gap 3), and the
emulator accepts it unchanged (shown by the run).

## 3. The HDOS H37 disk compared with the CP/M one

The `.h37` images are raw, so **neither image holds its IDs or
interleave.** What can be told:

| | CP/M (FORMAT 2.03) | HDOS H37 disk |
|---|---|---|
| geometry | SS SD 40 x 10 x 256 FM | the same (trailer) |
| R | 1-10 | 1-10. The label (HDOS sector 9) is at image offset 900H = R 10 of track 0, so HDOS sector s = track s / 10, R = s mod 10 + 1 (as HCOS's B.PHYS does) |
| C / H / N | cylinder / side / 01 | the same in SDUP37.ABS (below) |
| volume number | none | **not in the IDs** (SDUP37 puts the side in H). It is only in the label, `LAB.SER` = 01H at byte 0 (on the H17 it is also in every sector header) |
| interleave | 3, all tracks alike | Heath's own HDOS H37 INIT: [UNVERIFIED]. SDUP37 writes 1..10 in order (1:1) on even tracks and 9 10 1..8 on odd tracks (a 2-sector track skew; 16 sectors: rotated by 5) |
| T0S1 | CP/M label | HDOS boot code, no CP/M label (h37.md) |

The 1797 compares only C (the track register) and R. It never compares
H, so H could hold anything [datasheet, from memory; the emulator agrees].

**SDUP37.ABS** ("Super Duper Disk Duplicator V2.0", load 2280H) on the
HDOS disk formats H37 disks itself. Its FM template (2E47H) is Heath's,
except that the gap after the index is 32 FFH (not 16), the data fill is
AAH (55H on two-sided disks), and the buffer is padded with FFH to 3400
bytes. Its loop is `hlt / ldax d / out 7Bh / inx d / pchl`, after F4H OR
side. It steps with 4BH (Step In, no track-register update).

**`DK.DVD` on that disk has no WD1797 code.** It uses ports 7CH-7FH and
F2H (H17-style), whatever its "[NO]DKH37" option means [UNVERIFIED]. So
Heath's own HDOS H37 sector layout is unknown. Any layout with R = 1..10
works with HCOS's driver (physical = host + 1), and so does Heath's
CP/M stream.

## 4. Recommendation for HCOS

**Build the track in memory as Heath does** and only patch C (and H) for
each track. Working out bytes on the fly would cost about 131 T per FM
byte, which is possible, but MFM at 65 T isn't, and memory is free (FM
3.2K, MFM 6.4K). Keep Heath's stream exactly, so that disks are
identical to Heath's and the emulator is known to accept them.

```
; build (FM 10 x 256): HL -> trkbuf
        16 x FFh
        for slot = 0..9:
          6 x 00h, FEh
          idptr[slot] = HL          ; C H R come next
          00h, 00h, ilv[slot], 01h, F7h
          11 x FFh, 6 x 00h, FBh, 256 x E5h, F7h, 16 x FFh
        24 + 232 x FFh              ; slack to about 3302 bytes (> 3218)
; per track: for each slot  (idptr[slot]) = C, +1 = H
```

**Feeding.** Use the driver's own mechanism (dkisr jumps to `h37cmp`
with the status, `h37act` = 1, latch | CN.DRQ):

```
wtrk:   lxi  h,wdone ! shld h37cmp ! mvi a,1 ! sta h37act
        lda  latch ! ori CN.DRQ ! out DK.CON
        lxi  d,trkbuf
        mvi  a,0F4h ! ora side2     ; F4H, F6H for side 1
        lxi  h,wloop
        out  DK.CMD ! ei
wloop:  ldax d ! hlt ! out DK.DAT ! inx d ! pchl   ; the driver's wloop
wdone:  ...  latch back, status AND 0C4H (NR, WP, LD) = 0
             DE - trkbuf in [3070, 3302) or the speed is wrong
```

- **Timing.** DRQ is set as soon as the command is issued, so the first
  byte goes out within microseconds, well before the index (after the
  E delay). Per byte, Z80 at 2.048 MHz: the interrupt acknowledge and EI
  (about 10 T), `out` 11 T, `inx` 6 T, `pchl` 4 T and `ldax` 7 T come
  to about 40 T. That is against 131 T (FM, 64 µs) and 65 T (MFM), so
  both are fine. The DRQ from the next byte arrives about 32 µs (FM)
  after the OUT.
- **The clock** is held off while DRQ enable is set (h37.md). That is
  about 230-430 ms a track (E delay + wait for the index + one
  revolution), so the tick count lags. Heath lives with it.
  [UNVERIFIED on hardware]
- **A FORMAT entry in the BIOS.** `h37cmp`, `h37act` and `latch` are in
  biosram.inc and not public, and the motor timer (`dktck`) can switch
  the motor off between tracks. So the simplest safe design is a small
  driver op: "write track from DE" (and "step in" / "restore"). For
  example, generalise `xfer` to take DE and choose the loop by command
  bit 5 (88H read; A8H/F4H write), and keep `mtim37` at 0 while it runs.
  The other way is for FORMAT to take RST 4 and the latch over itself
  and restore them afterwards, which means knowing BIOS internals.

**Sequence (SS SD).** First select the drive and wait for the motor (dkrdy
for the index). Then Restore (03H) and check track 0. Then for t = 0..39:

1. patch C;
2. write the track;
3. verify it (below);
4. if t < 39, Step In 5BH (30 ms) and wait about 4 ms first, as Heath
   does.

After that, Restore and write the label sector, R = 1. For CP/M also
write the boot record and system tracks if requested (SYSGEN's job).
For HDOS, write the HDOS label (R 10 of track 0), GRT, RGT and directory
through B.PHYS (a separate design, like INIT; not covered here).

**Verify with Read Sector (88H, E = 0) in physical order.** Use the
interleave table (1, 8, 5, ...). After one data CRC the next ID is about
22 bytes (1.4 ms) away. Taking the INTRQ and issuing the next 88H takes
well under 0.5 ms, so a track verifies in about 1 revolution (plus up to
1 for the index). Reading R = 1..10 in numeric order would take about 3
revolutions. Read into a 256-byte scratch buffer through the driver's
rloop. A status AND 1CH (not found, CRC, lost data) that isn't 0 is a
bad track: retry the format once, then report it. A check that the data
is E5H is optional. The emulator times IDs by slot (`timeAt`), so
physical-order reads also save time there. Heath itself only does one
Seek-with-verify. Time per track: Heath's write takes about 0.4 s; with
the verify, about 0.6-0.8 s, so 40 tracks in about 30 s. [estimate]
