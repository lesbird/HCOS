# HCOS version 2: plan

- Status: **draft 0.6**, 2026-10-17. Phase 0 research done
  ([research/](research/): [boot.md](research/boot.md),
  [h17.md](research/h17.md), [h37.md](research/h37.md)). Phases 1-3
  done: HCOS v2 boots from an H17 disk to its own shell, BDOS and BIOS,
  and runs CP/M programs with Heath CP/M's 56K (section 7).
- Version 1 (the repo's top level; phases 1-6 in
  [../../docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)) runs on top of
  Heath CP/M: Heath's boot loader and BIOS, HCOS's BDOS and HCCP in the
  system tracks, HDOS programs through HDOS.COM. It works, but it boots as
  CP/M, HDOS programs run in a CP/M memory map, and the Heath BIOS limits
  what HCOS can do.

Decided (2026-10-17):

- **Disks:** CP/M format. HCOS boot disks are CP/M disks. HDOS disks are
  read and written, but not booted.
- **Order:** CP/M programs first, then HDOS programs.
- **Memory:** as much as possible. The target is **Heath CP/M's 56K**
  (BDOS at E200H on a 64K H89).
- **Machine:** the H89 first, the H8 later.
- **Tree:** version 2 is built in `v2/`, apart from version 1, which stays
  as it is.

## 1. Goal

A small operating system written from scratch. It boots quickly to its own
prompt, reads and writes CP/M and HDOS disks, and runs each kind of program
**natively**. Before each program starts, it sets memory up the way that
program's own operating system would:

- **A CP/M program** gets RAM at 0000H, page zero, the BDOS at (0006H) and
  a BIOS jump table at (0001H), and loads at 0100H.
- **An HDOS program** gets the monitor ROM and H17 ROM at 0000H-1FFFH, the
  HDOS system area at 2000H with the ROM's RST vectors working through it,
  and SCALLs at RST 7. It loads where its header says.

No Digital Research or Heath CP/M code is used: no CCP, no BDOS, no Heath
BIOS, no CP/M boot loader. The only code HCOS uses that it doesn't own is
the machine's ROM, which HDOS programs expect to find there. HCOS's H17
boot record also uses the ROM's sector read, R.READ, while the ROM is still
in (section 5).

### Non-goals for 2.0

- CP/M 3, banked memory, more than 64K.
- Booting from HDOS-format disks.
- HDOS loadable device drivers (`.DVD`). Native HDOS memory makes them
  possible later.
- Heath's CP/M utilities that call into the Heath BIOS's private tables
  (FORMAT, DUP, SYSGEN, CONFIGUR). HCOS gets its own FORMAT and SYSGEN.

## 2. What changes from version 1

| | Version 1 | Version 2 |
|---|---|---|
| Boot | Heath ROM boot, then the Heath CP/M boot loader, BIOS.SYS, and HCOS in the CP/M system tracks | Heath ROM boot, then HCOS's own boot record, system tracks and BIOS |
| BIOS | Heath CP/M's | HCOS's own: console, clock, H17, H37, memory switch |
| CP/M programs | HCOS BDOS on the Heath BIOS | The same BDOS, on HCOS's BIOS. 56K TPA |
| HDOS programs | HDOS.COM, a CP/M program. RAM at 0000H, a copy of the ROM routines | Native: ROM in, real RST vectors, the H17 ROM's own routines |
| HDOS disks from CP/M programs | HCOS.SYS hooked into the BDOS | The same idea: an extension loaded only when an HDOS disk is in use |
| Command processor | HCCP, a copy of the CP/M CCP | A new shell in the CCP's 2K, CCP compatible |
| Sign-on | Patched Heath BIOS string | HCOS's own |

## 3. Hardware

From the phase 0 research (section 8). Details and evidence are in
[research/](research/).

- **The memory switch:** port 362Q (F2H). Bit 5 maps RAM at 0000H and
  bit 1 enables the clock. The ROM leaves it at 82H and Heath's BIOS sets
  22H. The order is DI, OUT, write page zero, EI. The BIOS keeps the value
  in a cell and writes it again on every tick, as Heath's BIOS and
  HDOS 3.0 do.
- **Console:** the 8250 at 350Q (E8H). MTR-90 leaves it at 9600 baud
  (19200 with SW501 bit 6), 8N1, polled. HCOS polls (LSR bit 0 in, bit 5
  out). Ports FAH/FBH are the H8-5's, used only on an H8.
- **Clock:** a 2 ms interrupt on RST 1. With the ROM in, the ROM takes it
  and passes it on through 201FH. With RAM in, the BIOS takes it at 0008H.
  One 16-bit tick counter serves both, with the motor and settle timers.
- **H17:** Heath's BIOS drives ports 7CH-7FH itself with a 776-byte copy of
  the ROM's routines. HCOS does the same, modelled on the ROM. Interrupts
  are off from the header search to the end of the data. Every per-byte
  loop takes under 128 T-states, counted for the Z80. The volume number is
  ignored, so HDOS disks read too. One format: single-sided, 40 tracks.
- **H37:** a WD1797 behind ports 78H-7BH. Bytes move by a HALT/IN loop.
  DRQ ends each HALT, and INTRQ on RST 4 ends the transfer. Polling is too
  slow for double density at 2 MHz. Disks carry a label in sector 1 of
  track 0 that gives their DPB.
- **H8 (later):** PAM-8, the H8-4/H8-5 console, and its own ORG-0
  arrangement. The emulator can't test it. The console, clock and memory
  switch are kept in one small part of the BIOS so that the H8 can be
  added later.

## 4. Memory map (64K)

56K means the same top of memory as Heath CP/M 64K. Everything resident
while a CP/M program runs has to fit in E200H-FFFFH (7.5K), the room DRI's
BDOS and Heath's BIOS have.

```
Address   CP/M program                 HDOS program
--------  ---------------------------  ------------------------------
0000H     page zero (RAM)              monitor ROM
0100H     program (TPA)                ROM, H17 RAM 1400H, H17 ROM 1800H
2000H     ...                          HDOS system area
2280H     ...                          program (usual load address)
  ...                                    ...
                                       (S.SYSM)
                                       SCALL layer + HDOS file system
                                         (loaded for HDOS programs)
          [HDOS extension, only when an HDOS disk is in use]
DA00H     shell (2K, transient, may be overwritten, like the CCP)
E200H     BDOS (entry E206H): CP/M 2.2 calls and the CP/M file system
F000H     BIOS: jump table, console, clock, H17, H37, memory switch,
          buffers, allocation vectors
FFFFH
```

- **The BDOS** is version 1's, checked against DRI's. It stays at E200H,
  3.5K with its variables and stack, as in version 1.
- **Measured (phase 3):** the BIOS with the H17 driver, warm boot's
  reload and the ready check is 1696 bytes of code and tables, of the 1792
  the reserved tracks give it. The H17 driver alone is about 650 bytes and
  deblocking 336, more than the estimates below (490 and 220). So the H37
  driver won't fit until something gives:
  - trimming;
  - moving the cold boot into the boot record's sector (187 bytes free)
    or the BDOS's space (457 bytes free after its code, but its variables
    are there);
  - loading the H37 driver from a file at cold boot.
- **The BIOS** has 4K at F000H. Its jump table has the 17 CP/M 2.2 entries
  at F000H, so programs that call the BIOS directly keep working. One BIOS
  drives both the H17 and the H37. The research estimates:

  | Part | Bytes |
  |---|---|
  | Jump table, disk entries, deblocking (DRI's algorithm, 256-byte host sectors) | 350 |
  | H17 driver | 490 |
  | H37 driver, SS SD / + DS and 256-byte MFM | 300 / 450 |
  | Console, clock, memory switch, warm boot, messages | 270 |
  | DPHs, DPB, skew, drive tables | 155 |
  | **Code and tables** | **1.55-1.7K** |
  | Host buffer 256, DIRBUF 128, ALV/CSV for 6 drives 170-440, variables and stack 100 | 0.65-0.9K |
  | **BIOS** | **2.2-2.6K** |

  Heath's H17/H37 BIOS needs 5.8K, which is why Heath's H17/H37 CP/M has
  only a 54K TPA. HCOS leaves out 1024-byte sectors (they need a
  1024-byte buffer), double-stepping, the I/O byte, printers and
  type-ahead.
- **Spare room:** the 1.4-1.8K left at the top of the BIOS area can be
  spent later. It could hold more BIOS (1024-byte sectors, type-ahead), or
  it could move the BDOS and shell up for a TPA over 56K. A higher TPA
  means a CP/M that differs from Heath's layout, so it waits until
  everything works.
- **The shell** is 2K at DA00H, like the CCP, so programs that keep the CCP
  (top of TPA = (0006H)-0806H) and return to it with RET work as on CP/M.
- **HDOS disks, from CP/M programs:** the HDOS file system is an
  extension, the file `HDOSFS.SYS` (version 1's HCOS.SYS, about 4K). It goes below the shell only while
  an HDOS disk is logged in, so the TPA is 56K unless it is in use. The
  BDOS marks a drive as HDOS when it logs it in. At the next warm boot the
  shell loads the extension and hooks it in, as in version 1. A CP/M
  program that logs in an HDOS disk for the first time without the
  extension gets a select error. Running it again works. `DIR B:` at the
  prompt is enough to load the extension.
- **HDOS programs:** for an `.ABS`, the loader reads the SCALL layer and
  the HDOS file system into the top of the HDOS program area, below the
  shell. CP/M disks work from HDOS programs through the BDOS, as with
  HDOS.COM. This is about 8K, so HDOS programs get about 2280H-C800H,
  against real HDOS 2.0's EDB0H. Getting more back is in section 9.

## 5. Booting

1. **The ROM's boot.** From the H17, MTR-90 reads sectors 0-8 of track 0
   (2304 bytes) to 2280H with the ROM's R.READ, and jumps there. From the
   H37 it reads all of track 0 from sector 1 (2560 bytes) to 2280H. It
   tries double density first. The ROM is still in, interrupts are on,
   SP is 2280H and port F2H holds 82H.
2. **Everything goes in the reserved tracks.** The Heath CP/M formats
   reserve 3 tracks, 7680 bytes. HCOS needs the boot record (256 bytes),
   the shell (2K), the BDOS's code (3.1K) and the BIOS's code and tables
   (about 1.7K): about 7.1K. The buffers and variables aren't stored on
   disk. So there is **no HCOS.SYS file**. The disk stays an ordinary
   Heath CP/M disk, and SYSGEN writes only the reserved tracks. If the
   BIOS outgrows the space, its cold-boot code goes in a file instead.
3. **The boot record** loads the reserved tracks and moves each part
   into place.
   - **H17:** with the ROM's R.READ (1C3FH: HL = sector 0-399, DE =
     buffer, BC = bytes; carry and A on error), as Heath's CP/M boot record
     does. It must keep interrupts on and not HALT (the ROM's clock takes a
     HALT as a drop to the monitor). It must leave 2000H-20BEH, 201FH and
     2131H alone, which the ROM uses.
   - **H37:** MTR-90 has no reusable read. The boot record has its own
     1797 read loop of about 100 bytes, as Heath's does.

   Then: DI, `OUT F2H,22H`, write page zero, EI, and jump to the BIOS's
   cold boot.
4. **Warm boot** (^C, JMP 0, function 0) reloads the shell from the
   reserved tracks only if its checksum is wrong. The BDOS is reloaded only
   if *its* checksum is wrong. After a small program the prompt comes back
   with no disk access.

There's no date question. The date comes from the last `DATE` set,
saved on the boot disk, and HDOS programs see it in S.DATE.

**Speed:** measured in the emulator, the prompt appears **3.2 s after
reset**. Heath CP/M on the same disk takes 5.7 s. About 1.2 s is MTR-90
before the boot record runs, about 1 s the 30-sector read, and about 1 s
the shell's disk reset, which logs in drive A: and reads its directory, as
CP/M's CCP does. (With phase 1's test shell, which doesn't touch the disk,
it was 2.2 s.) The BIOS leaves the motor running from the ROM's boot, so
that first access doesn't wait 1 s for it.

## 6. Shell

The shell has to fit the CCP's 2K, so it is HCCP's CCP behaviour with
little added:

- built-ins DIR, ERA, REN, SAVE, TYPE, USER, with CAT as DIR;
- SUBMIT through $$$.SUB;
- `NAME` runs NAME.COM, then NAME.ABS;
- HDOS names (`SY1:`) taken as drive letters;
- the extension loaded when a logged-in drive is HDOS.

Everything else is a program on the disk, for example:

- FORMAT (CP/M or HDOS format, H17 or H37);
- SYSGEN (make a disk bootable);
- DRIVES (what's in each drive);
- DATE.

Copying between formats needs no special command, because PIP works on
HDOS disks.

## 7. Phases

Each phase ends with tests in the emulator, as in version 1: differential
where there's a real system to compare with.

| Phase | Deliverable | Proves |
|---|---|---|
| 0 | Tag `v1.0`; set up `v2/`. The research in section 8 | the unknowns before code |
| 1 | **Done.** H17 boot record and BIOS skeleton: cold boot from the reserved tracks, console with a type-ahead buffer, clock, memory switch, a test shell. `tools/mksys.py` writes the reserved tracks of a copy of a Heath CP/M disk. Measured in the emulator: the prompt 2.21 s after reset, against 5.71 s for Heath CP/M. Sizes: boot record 61 bytes, BIOS 376 | own boot; boot time |
| 2 | **Done.** The H17 driver in the BIOS (`src/bios/h17.asm`): read and write, with retries, motor and seek timing, not-ready and write-protect errors, the volume ignored. DRI's blocking/deblocking, with Heath's skew applied in the BIOS (the DPH has no XLT). Tests: the test shell reads a whole disk (CP/M and HDOS) and writes with each write type, and `tests/h17img.py` checks the sums and the image byte for byte. A whole disk reads in 41 s (4 turns a track for the skew, plus the steps). BIOS: 1426 bytes | own disk driver |
| 3 | **Done.** Version 1's BDOS (`src/bdos/`) and HCCP as the shell (`src/shell/shell.asm`) on the new BIOS: `build/hcos.h8d` boots HCOS. BDOS entry E206H, as Heath CP/M 64K: a 56K TPA. Warm boot checks the shell's and the BDOS's sums (kept in the boot sector by `mksys.py`) and reloads only what a program changed. SELDSK checks that a drive is ready the first time, as Heath's does. `tests/cpmdiff.sh` runs v1's CP/M tests (ASM, DDT, ED, PIP, STAT, SUBMIT, the CCP built-ins, console and file calls) on Heath CP/M and on HCOS: the screens are the same. Prompt 3.2 s after reset (Heath CP/M: 5.7 s). Sizes: shell 1866, BDOS 3127, BIOS 1696 bytes | CP/M programs native, 56K |
| 4 | The HDOS extension for CP/M programs (version 1's HCOS.SYS moved across as HDOSFS.SYS), loaded on demand | HDOS disks |
| 5 | HDOS programs natively: ROM in, system area, SCALLs, .LINK, .LOADO, ^C handlers. `difftest.sh` against real HDOS 2.0, BASIC | HDOS programs native |
| 6 | H37 driver and boot record. Formats: SS SD 10 x 256 (both H37 images), then DS and 16 x 256 MFM. Labels read as Heath's BIOS does | second controller |
| 7 | FORMAT, SYSGEN, DRIVES and DATE as programs. A disk HCOS makes boots HCOS | self-hosting |
| 8 | Sizes trimmed, ready-made disks in `v2/disks/`. Release 2.0 | |
| 9 | (later) The H8; the ideas in section 9 | |

## 8. Research (phase 0): done

| # | Question | Answer | Notes |
|---|---|---|---|
| R1 | What the ROM's boots load; can a boot record use the ROM's read | H17: sectors 0-8 to 2280H, and yes, R.READ works for any sector on any drive (tested). H37: track 0 to 2280H, and no reusable read | [boot.md](research/boot.md) |
| R2 | How to drive the H17 | Ports, sector format, checksum, timing and Heath's driver, all written up. Model it on the ROM, start the header search early, ignore the volume | [h17.md](research/h17.md) |
| R3 | How to drive the H37 | HALT/DRQ transfer, INTRQ on RST 4, 4 retries, density by trial, label in T0S1 | [h37.md](research/h37.md) |
| R4 | DPBs and recognition | H17: one fixed DPB (SPT 20, 1K blocks, DSM 91, DRM 63, OFF 3, skewed). H37: DPB from the disk's label, default SS SD | [h17.md](research/h17.md), [h37.md](research/h37.md) |
| R5 | Console and clock | 8250 polled at 9600 (or 19200); F2H bits 1 and 5; Heath's FAH/FBH are the H8-5 | [boot.md](research/boot.md) |
| R6 | How much room the BIOS needs | Heath's H17 BIOS: 3764 bytes, of which the driver is 776. HCOS's: about 2.2-2.6K with both drivers | section 4 |
| R7 | HDOS programs that call the ROM's disk routines | Not yet: it belongs to phase 5. The BIOS must forget every drive's track after an HDOS program runs | [h17.md](research/h17.md) |

**Not confirmed by the research:**
- The gap layout on real Heath-formatted H17 disks. The emulator has
  header sync at byte 10, which leaves Heath's driver a margin of about 1.5
  bytes.
- Whether the real H37 card holds off the clock interrupt during a
  transfer, as the emulator does.
- What the emulator doesn't model at all: step rate, motor spin-up, head
  settling and overruns. The first real-hardware test is the check for
  them.

## 9. Later: getting memory back

- **HDOS programs:** keep only the current HDOS disk's GRT, and read it
  again when the drive changes (about 768 bytes back with four drives).
- **HDOS programs:** the H17's 1K of RAM at 1400H is visible with the ROM
  in. The SCALL layer could keep its buffers there.
- **HDOS programs:** the shell isn't needed while an HDOS program runs, so
  that space is theirs too.
- **CP/M programs:** the shell could shrink below 2K, but CP/M programs
  expect the CCP to take 2K, so the TPA wouldn't grow.

## 10. What version 1 gives version 2

Files are copied into `v2/` as each phase needs them. Version 1 is left
untouched and builds from the top level and from the `v1.0` tag.

| Copied and adapted | Replaced | Not used |
|---|---|---|
| `bdos.asm` (CP/M 2.2, checked against DRI's) | Heath BIOS, with HCOS's | `sysgen.py` (replaced by a v2 host tool for the whole reserved tracks) |
| `hccp.asm`, cut down to the shell | HDOS.COM's `bios.asm` calls, with calls to HCOS's BIOS | `romlib.asm`, while the real ROM is in |
| `hdosfs`, `hdoswr`, `hdosdir`, `kfb`, `kxlib` (the HDOS extension) | H-mode's per-SCALL switching (no longer needed) | |
| `scall`, `console`, `files`, `sysarea`, `systab`, `syndir` (the SCALL layer) | | |
| The test harness and tests | | |
