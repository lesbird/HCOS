# R: An empty HDOS 2.0 disk, as INIT makes it

What HCOS FORMAT has to write so that real HDOS 2.0 mounts and uses the
disk (H17, or H37 SS SD: both 40 x 10 x 256 = 400 sectors).

**Sources.** HDOS 3.0 INIT source (`testHdos/source/init.h8a`), mount
(`mnd.acm`, `getlab.acm`), SYSGEN (`sysgen.h8a`) and the decks LABDEF,
DIRDEF (3.0 in `acm/`, 2.0 in `acm2/`), DISDEF, DIFDEF, all from
github.com/mgarlanger/asmx. HDOS 2.0 INIT.ABS from the HDOS 2.0 disk,
disassembled (load 2480H, 7424 bytes). Its FOV/ADB/BGT/IDD code is the
same as 3.0's, minus the 3.0-only fields. Also three disks: the HDOS 2.0
system disk (`H89/disks/HDOS_2-0_System.h8d`), `v2/build/hdos.h8d` and
the H37 HDOS disk (`HDOS-2-H37IMGR-AND-H8DIMGR3_*.H37`), all three made by
INIT. Every structure below matches them byte for byte, apart from the
files on them.

**Result.** `mkhdos.py` (below) builds the disk. Tested in the emulator
with real HDOS 2.0: MOUNT, CAT /S, PIP both ways (compared on the host),
on H17 and H37. HDOS 2.0 SYSGEN made it a system disk, and that disk
booted. HCOS's own `udet` recognised it too.

## 1. Parameters (H17 and H37, 400 sectors)

These come from INIT 2.0 (2480H code, 35F7H-365CH) and the driver's INIT
subfunctions (2: the directory interleave table, 3: SIZ/PSS/VFL and SPT).

| Name | Formula (INIT) | Value |
|---|---|---|
| SPG, sectors a group | `((SIZ+255)/256 + 1) AND 0FEH` | 2 |
| NGROUPS | SIZ / SPG (must be < 256) | 200 |
| NSPCGRP, special groups | `max((10+SPG-1)/SPG, 2)` | 5 (groups 0-4 = track 0) |
| RGT sector | NSPCGRP x SPG | 10 (group 5) |
| Directory entries a group | SPG x 22 / 2 (a 512-byte block holds 22) | 22 |
| Directory groups | (NGROUPS-NSPCGRP)/22 + 1 | 9 (198 entries) |
| Where the search starts | (NGROUPS-NSPCGRP)/3 | group 65 |
| Directory + GRT area | 10 groups from 65, all RGT=01 | groups 65-74 |
| GRT group | the last one | 74 = sector 148 |
| Directory interleave (DBI) | from the driver | H17 SY.DVD: `1,3,0,2,4,6,8,5,7`. H37 SY.DVD: `0,1,...,8` |
| Directory groups, in chain order | 65 + DBI[i] | H17: 66,68,65,67,69,71,73,70,72. H37: 65..73 |
| LAB.DIS | first group in chain x SPG | H17 132, H37 130 |
| Free | 200 - 5 - 1 (RGT) - 10 | 184 groups = 368 sectors ("368 Free" in CAT) |

If a group of the 10 is bad (RGT=FFH), INIT moves on and, failing that,
starts again from group 2. A disk that tests good doesn't need this.

## 2. Label, sector 9 (LABDEF; INIT's template is at 38AEH)

| Off | Field | Fresh data disk | Notes |
|---|---|---|---|
| 00 | LAB.SER | 1-255 | Volume serial. 2.0 INIT asks "from 1 to 255" and rejects 0. The distribution disk has 0, and HDOS mounts that too. HDOS sets the driver's volume to it (see 4) |
| 01 | LAB.IND (2) | S.DATC | Coded date: `(yy-70)<<9 | month<<5 | day`. 01-Jan-77 = 0E21H, 14-Oct-86 = 214EH |
| 03 | LAB.DIS (2) | 132 (H17) / 130 (H37) | First directory sector |
| 05 | LAB.GRT (2) | 148 | GRT sector |
| 07 | LAB.SPG | 2 | |
| 08 | LAB.VLT | 0 | 0 data, 1 system (SYSGEN sets it), 2 no directory |
| 09 | LAB.VER | 20H | 2.0. SYSGEN 2.0 wants exactly this. HDOS 3.0 reads a disk with VER < 30H as 2.0 format |
| 0A | LAB.RGT (2) | 10 | Mount ignores it if VER < 17H and uses 10 |
| 0C | LAB.SIZ (2) | 400 | |
| 0E | LAB.PSS (2) | 256 | |
| 10 | LAB.VFL | 0 | bit 0 two sides, bit 1 96 tpi (3.0), bit 2 fixed (3.0) |
| 11 | LAB.LAB (60) | text, blank-filled | INIT fills 61 bytes (60 + one blank) |
| 4E | (reserved) | 00 | The "0 byte" that ends the label text |
| 4F | LAB.SPT | 10 | |
| 50-FF | (LAB.LVN is 3.0 only) | 00 | INIT 2.0 leaves junk from memory here. Zeros are fine |

**Checks at mount** (`mnd.acm`, 3.0; 2.0 does the same [UNVERIFIED for
2.0]). The label read must succeed (EC.DNR otherwise). VLT >= 2 gives
EC.DNI. VER picks the RGT address (and 2.0 or 3.0 format in 3.0). SER
goes to the driver as the volume. GRT, DIS and SPG go into the unit
table. HDOS uses no checksum or magic number. SIZ, PSS and SPT are read
by HCOS (`udet`: PSS=256, SPT=10, SPG 1-8, DIS and GRT < SIZ; and the
BDOS's `hdchk`: PSS and SPT). Boot (T0BOOT) checks VLT: 0 gives "?00 THIS
DISK MUST BE SYSGENED", other values not 1 give "...MUST BE INITIALIZED
AND THEN SYSGENED".

## 3. RGT.SYS (sector 10), GRT.SYS (sector 148)

One byte for each group, 256 bytes.

| Group | RGT | GRT |
|---|---|---|
| 0 | 00 | **head of the free chain** (first free group, 0 if none) |
| 1 | 00 | 00 |
| 2-4 (rest of track 0) | FF reserved | FF |
| 5 (RGT.SYS) | 01 | 00 (one-group chain) |
| directory groups | 01 | next group in DBI order. The last one is 00 |
| 74 (GRT.SYS) | 01 | 00 |
| other 6-199 | 01 (usable) | free chain, ascending: g -> next free group, the last one 00 |
| 200-255 (past the end) | FF | FF |

In the RGT, 01 means usable and FFH means reserved or bad. INIT's bad
sector list puts FFH at sector/SPG (sectors 0-10 not allowed). The GRT
starts as a copy of the RGT. INIT then sets the RGT.SYS group to 00,
links the directory and GRT groups, and links every group still 01 into
the free chain, working down from 255. File chains work the same way:
GRT[g] is the next group, and 0 ends the file.

H17 fresh-disk GRT, bytes 40H-4FH: `4B 43 44 45 41 47 48 49 00 46 00 4C 4D 4E 4F 50`.
Free chain: 6..64, then 64->75 (`GRT[40H]=4BH`), 75..199. GRT[0]=06, GRT[0C7H]=00.

## 4. DIRECT.SYS (groups 65-73)

**Block** (DISDEF): 512 bytes, which is 2 sectors and so 1 group when SPG=2.

| Off | Contents |
|---|---|
| 000-1F9 | 22 entries of 23 bytes |
| 1FA | 00 (ends the entries) |
| 1FB | DIS.ENL = 17H (23) |
| 1FC (2) | DIS.SEC: this block's sector |
| 1FE (2) | DIS.LNK: the next block's sector, in GRT-chain order. The last block has 0 |

The DIS.LNK order and the GRT chain of DIRECT.SYS must agree. HDOS
searches by DIS.LNK and CAT reads DIRECT.SYS as a file.

**Entry, 2.0** (`acm2/dirdef.acm`). The bytes after the name (11-22):

| Off | Field | Value in the special entries |
|---|---|---|
| 00 | name (8), 00-padded | First byte FFH (DF.EMP) means empty. FEH (DF.CLR) means empty, and so is the rest of the directory: searching stops there |
| 08 | ext (3) | `SYS` |
| 0B, 0C | DIR.PRO, DIR.VER | 00 00 |
| 0D | DIR.CLU | 00 |
| 0E | DIR.FLG | F0 for RGT and GRT (SYS+LOC+WP+CNT), E0 for DIRECT (no CNT, because the interleave makes it non-contiguous) |
| 0F | (reserved) | 00 |
| 10 | DIR.FGN | RGT 5 / GRT 74 / DIRECT = first group in chain (66 H17, 65 H37) |
| 11 | DIR.LGN | RGT 5 / GRT 74 / DIRECT = last group in chain (72 H17, 73 H37) |
| 12 | DIR.LSI | 1 / 1 / SPG (2) |
| 13 | DIR.CRD (2) | S.DATC (INIT 2.0 sets it, at 331CH. The distribution disk has 0) |
| 15 | DIR.ALD (2) | S.DATC |

**Contents of a fresh directory** (INIT's IDD, with the same bytes from
the disks):

| Block (chain order) | Entries |
|---|---|
| 1st | 22 x (FF + 22 x 00) |
| 2nd | 0-17: FF + zeros; 18: RGT.SYS; 19: GRT.SYS; 20: DIRECT.SYS; 21: FE + 22 bytes of junk (2.0: `GAC / HEATH CO.JGL))\n\n`. Zeros are fine) |
| 3rd-9th | 22 x (FE + 22 x 00) |

CAT /S shows `RGT.SYS 1`, `GRT.SYS 1`, `DIRECT.SYS 18`, flags SLW.

## 5. Track 0 and the volume number

| Sectors | What INIT writes |
|---|---|
| 0-1 | The running system's boot sectors (2280H-247FH, starting `C3 A0 22`) [UNVERIFIED for 2.0: read from the 3.0 source's RPB, but the bytes match] |
| 2-8 | T0BOOT, INIT's first 7 sectors (2480H-2B7FH), on **every** disk, data or system |
| 9 | the label |

On a data disk, the boot code just prints "?00 THIS DISK MUST BE SYSGENED
BEFORE IT CAN BE USED." and halts. **HDOS SYSGEN doesn't write sectors
0-8.** It copies the files and sets VLT=1 (both checked: the sectors were
the same after a 2.0 SYSGEN). So:

- For a non-bootable data disk, sectors 0-8 can be anything. HDOS mount
  never reads them. A small HCOS stub that says "not a system disk" is
  better than zeros, because the ROM jumps to 2280H.
- For a disk HDOS SYSGEN can make bootable, copy sectors 0-8 from any
  INIT-made HDOS 2.0 disk (e.g. SY0:). Tested: FORMAT image + the 0-8 of
  `hdos.h8d` -> HDOS SYSGEN SY1: ("13 Files Copied") -> boots HDOS 2.0
  from it ("Volume 005, Mounted on SY0:").

**H17 header volume.** HDOS writes volume 0 in the headers of track 0 and
LAB.SER in the headers of tracks 1-39 (see h17.md 3.3). Mount reads the
label as volume 0, then gives the driver LAB.SER, and the ROM's R.LPS
compares it. **So HCOS FORMAT must format tracks 1-39 with the volume set
to LAB.SER**, or use SER=0 everywhere, which HDOS accepts (the
distribution disk). The emulator takes the volume for .h8d images from
the label, so it can't catch a mismatch. Mismatched headers failing on
real HDOS is [UNVERIFIED on hardware]. The H37 (1797) ID field has no
volume, so on the H37 the SER is only in the label.

## 6. Bad sectors

INIT asks for bad sectors after the surface test and puts FFH in the RGT
group (and so in the GRT). Groups 0-4 are always reserved. If a group
among the 10 directory/GRT groups is bad, ADB slides the area along (see
1). FORMAT can ignore all of this if verify finds no errors. If it does
find errors, the simplest course is to mark the group FFH in the RGT and
GRT, refusing the disk if the bad group is 5 or 65-74.

## 7. Recipe for HCOS FORMAT (400-sector H17 disk)

1. Format 40 tracks: track 0 volume 0, tracks 1-39 volume SER (H17). Fill
   the data with E5H or anything.
2. Write sectors 0-8: an HCOS stub, or a copy of an HDOS disk's 0-8.
3. Sector 9, the label: `SER, IND(2)=S.DATC, 84 00, 94 00, 02, 00, 20, 0A 00,
   90 01, 00 01, 00`, then 61 bytes of text blank-filled, `00`, `0A`, and
   zeros to 256. (H37 with sequential DBI: DIS=`82 00`.)
4. Sector 10, the RGT: `00 00 FF FF FF`, 195 x `01` (groups 5-199), 56 x `FF`.
5. Sector 148, the GRT: the RGT with the changes in 3, i.e. [0]=06,
   [5]=00, the directory chain, [74]=00, the free chain.
6. Sector 149: anything (the rest of the GRT group; INIT leaves it).
7. Directory groups in chain order (H17: 66,68,65,67,69,71,73,70,72):
   each 512-byte block as in 4, with SEC = group x 2 and LNK = the next
   one's sector (the last 0).
8. Everything else: anything. It is free space.

H37: the same with DBI `0..8`. HDOS follows the links, so either DBI
works on either drive. Using each driver's own table makes the disk the
same as INIT's.

## 8. Script and tests

`mkhdos.py` builds the disk:
`/private/tmp/claude-501/-Users-lesbird-Projects-Claude-HCOS/eb1005e6-400d-4475-954a-e36213886382/scratchpad/hinit/py/mkhdos.py out.h8d [--h37] [--seq] [--ser N] [--date 14-Oct-86] [--label TEXT] [--boot file]`.
`hdump.py` (same folder, `hdump.py image [offset]`) prints a disk's
label, GRT, RGT, free chain and directory. Results, all in the emulator:

| Test | Result |
|---|---|
| Structure against the 3 INIT-made disks | RGT, directory trailers and chain the same. H37 special entries byte-for-byte the same |
| HDOS 2.0 (hdos.h8d in SY0), made disk in SY1: MOUNT, PIP INIT.ABS and SYSHELP.DOC on, PIP back, DISMOUNT/MOUNT, CAT /S | "Volume 007, Mounted on SY1:", 334 free. Files compared on the host: the same |
| H37 HDOS disk booted (`--sw501 30 --dk0`), made `--h37` disk in dk1 | MOUNT, PIP on and PIP SY1:->SY1:, the same on the host |
| HCOS (`hcos.h8d`), made disk as B: | HDOSFS loaded, PIP XSUB.COM [V], DIR, STAT 91k. h8dtool reads the result |
| Made disk + HDOS sectors 0-8, then HDOS SYSGEN SY1:, then boot it | boots HDOS 2.0, CAT works |
| HDOS 2.0's DK.DVD with an H37 disk | MOUNT DK0: hangs (that driver isn't the H37's). Use the H37 HDOS disk's SY.DVD |

Emulator command (H17):
`h89run --disk0 sys.h8d --disk1 made.h8d --seconds 150 --step 'H: |B\r'
--step 'ACTION?|\r' --step ')?|14-Oct-86\r' --step '>|MOUNT SY1:\r'
--step '>|PIP SY1:X.ABS=SY0:INIT.ABS\r' --step '>|CAT SY1:/S\r'`. HDOS 2.0
needs `MOUNT SY1:` before it uses the disk.
