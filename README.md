# HCOS — HDOS CP/M Operating System

HCOS is one operating system for the Heathkit **H8 and H89** that runs
both of the machines' software libraries:

- **CP/M 2.2** programs (`.COM`), unchanged;
- **HDOS 2.0** programs (`.ABS`), unchanged.

Either kind can use either kind of disk. It is written in pure 8080
assembly, so it runs on the H8's 8080A as well as the H89's Z80. It boots
from an ordinary Heath CP/M disk and uses the Heath BIOS for the hardware.

Status: **phases 1–6 of the [roadmap](docs/ARCHITECTURE.md#13-development-roadmap)
are done.**

- HCOS boots from H17 and H37 disks.
- It passes 60 automated tests, most of them comparisons with the real
  operating systems. They run on [lesbird/H89](https://github.com/lesbird/H89),
  an H89 emulator accurate enough to boot and run real Heath CP/M and HDOS.

## What it can do

### Run CP/M programs, as CP/M does

HCOS has its own BDOS (the CP/M system calls) and its own command
processor. Neither contains Digital Research code. CP/M programs see the
same system:

- the same calls;
- the same messages and error behaviour;
- the same 48–56K of memory.

STAT, PIP, ED, DDT, SUBMIT, ASM and LOAD have been checked by running the
same keystrokes on Heath CP/M and on HCOS and comparing the screens. They
are identical.

### Run HDOS programs by typing their names

When there is no `NAME.COM`, the command processor runs `NAME.ABS`, an HDOS
program:

```
A>BASIC
Extended Benton Harbor BASIC #110.06.00
*10 PRINT "HELLO FROM HDOS BASIC ON HCOS"
*RUN
HELLO FROM HDOS BASIC ON HCOS
End At Line  65535
*SAVE "B:HELLO.BAS"
*BYE
Sure?Y
A>
```

- HDOS system calls (SCALLs) are carried out by HCOS's HDOS personality.
- Console handling, line editing, ^C handlers, file channels, `.LINK`
  chaining and error messages behave as on HDOS 2.0. Test programs run
  on real HDOS 2.0 and on HCOS must print the same thing.
- The HDOS 3.0 calls `.GDA` and `.CRC16` are there too.

### Use HDOS disks from CP/M programs

An HDOS disk in a drive is just a disk to CP/M programs:

```
A>DIR B:
B: EDIT     ABS : BASIC    ABS : PATCH    ABS : INIT     ABS
B: SYSGEN   ABS
A>PIP B:=A:XSUB.COM[V]
A>DIR B:
B: EDIT     ABS : BASIC    ABS : PATCH    ABS : INIT     ABS
B: SYSGEN   ABS : XSUB     COM : HELLO    BAS
```

That's CP/M's PIP copying onto an HDOS disk, with verify, and CP/M's DIR
listing it. HELLO.BAS is the program HDOS BASIC saved there above. ERA,
REN, TYPE and random-access files work too. Real HDOS 2.0 boots and reads
disks written this way. (Files with HDOS's S flag are hidden, as CP/M hides
SYS files.)

### Use CP/M disks, and HDOS disks, from HDOS programs

HDOS PIP lists and copies files on CP/M disks and on HDOS disks.

HDOS PIP's listing of an HDOS disk in drive B:, with real dates, flags and
free space:

```
:P:SY1:/L/S
Name    .Ext    Size      Date          Flags   01-Jan-80
...
BASIC   .ABS    42      03-Nov-80       W
SYSHELP .DOC    3       03-Nov-80       SW
DIRECT  .SYS    18       No-Date        SLW
   21 Files, Using 316 Sectors (62 Free)
```

On a CP/M disk, HDOS programs see an HDOS directory built from CP/M's,
with correct sizes and free space.

### Run programs that need the ROM

Some HDOS programs call routines in the monitor ROM, or read it. HCOS
normally runs with RAM at address 0, where CP/M needs it. A program listed
in `HCOS.CFG`, or run as `HDOS /R NAME`, runs with the ROM switched in
instead (H-mode), as on real HDOS.

`HCOS.CFG`:

```
ROMPROG ROMMODE
```

Part of the output of the test program `ROMMODE`, typed at the HCOS
prompt. It reads the ROM's bytes at 0000H, calls the monitor's delay
routine, and types through the H17 ROM's `$TYPTX`:

```
A>ROMMODE
ROM C3 00 04 21 DLY OK
TYPTX OK
```

### H17 and H37

HCOS boots from the H17 (hard-sectored) and from the H37 (soft-sectored,
single density). The H37 HDOS disk's programs run too, such as the Z80
program `H89 PIE 1.5b Editor`.

### HDOS programs on plain CP/M

The HDOS personality is an ordinary CP/M program, `HDOS.COM`. On Heath
CP/M, without the rest of HCOS, `A>HDOS BASIC` runs HDOS BASIC. Everything
above about HDOS programs works there too. Running them by name, and CP/M
programs using HDOS disks, need the rest of HCOS.

## How it works

```
   CP/M program (.COM)                HDOS program (.ABS)
   CALL 5 ──────┐                     RST 7 + function byte (SCALL)
                │                              │
                │                     ┌────────▼─────────┐
                │                     │ HDOS personality │  HDOS.COM,
                │                     │ SCALL dispatcher │  loaded for
                │                     │ HDOS system area │  .ABS programs
                │                     │ H17 ROM library  │  (0100H-1FFFH)
                │                     └──┬───────────┬───┘
         ┌──────▼──────┐   CP/M disks    │           │   HDOS disks
         │  HCOS BDOS  ◄─────────────────┘           │
         │ (CP/M 2.2)  │                             │
         └──┬───────┬──┘                             │
  CP/M disks│       │HDOS disks: offered to          │
            │  ┌────▼────────────┐                   │
            │  │ HCOS.SYS:       │    HDOS file system (same source)
            │  │ KFB + HDOS FS   │                   │
            │  └────┬────────────┘                   │
         ┌──▼───────▼──────────────────────────────── ▼──┐
         │          Heath BIOS: console, H17, H37, LP     │
         └────────────────────────────────────────────────┘
```

### The parts

| Part | What it is | Where it lives |
|---|---|---|
| **BDOS** | CP/M 2.2 system calls and file system, written from the CP/M documentation. 3.1K. | System tracks; loaded on every boot |
| **HCCP** | The command processor: CP/M's built-ins and messages, SUBMIT, `CAT`, and running `.ABS` programs. 2K. | System tracks |
| **HCOS.SYS** | Kernel extension: the HDOS file system, and **KFB**, which runs CP/M's FCB calls on HDOS disks. 5.5K. | A file, loaded at cold boot below the CCP |
| **HDOS.COM** | The HDOS personality: SCALLs, the emulated HDOS system area, console, channels, the HDOS file system, and the H17 ROM's utility routines. 8K. | A file, loaded when an `.ABS` runs |
| **Heath BIOS** | Hardware drivers (unchanged). | BIOS.SYS, as on Heath CP/M |

### Booting

1. **The monitor ROM** loads the boot loader, the command processor, the
   BDOS and a small loader BIOS from the disk's system tracks.
   `tools/sysgen.py` has put HCCP and the HCOS BDOS there.
2. **The HCOS BDOS** loads the Heath BIOS from `BIOS.SYS` for the loader
   BIOS, then starts the BIOS.
3. **The BIOS** enters HCCP. At cold boot HCCP loads `HCOS.SYS`. On every
   boot it hooks HCOS.SYS into the BDOS and lowers the top of program
   memory (0006H) to protect it.
4. **Warm boot** (^C, or a program ending) reloads HCCP and the BDOS from
   the system tracks, as CP/M does. HCOS.SYS stays in memory: HCCP finds it
   by its signature and resets it.

### Memory (64K H17 system)

| Address | Contents |
|---|---|
| 0000H-00FFH | CP/M page zero (RST 7 points at the SCALL dispatcher while an HDOS program runs) |
| 0100H-C1FFH | CP/M programs (48.5K). HDOS.COM sits in 0100H-1FFFH while an HDOS program runs. |
| 2000H-227FH | Emulated HDOS system area (for HDOS programs) |
| 2280H- | HDOS programs |
| C200H-D8FFH | HCOS.SYS |
| DA00H-E1FFH | HCCP |
| E200H-EFFFH | BDOS |
| F000H-FFFFH | Heath BIOS |

On the H17/H37 Heath CP/M, whose BIOS is bigger, everything above the
programs is 800H lower. The kernel is built for both
(`build/kernel/h17/`, `build/kernel/h37/`).

### Two personalities, one set of files

- **HDOS programs and CP/M disks.** An HDOS program's file calls on a
  CP/M disk become BDOS calls. A 256-byte HDOS sector is two 128-byte CP/M
  records.
- **CP/M programs and HDOS disks.** The BDOS offers each FCB call to
  HCOS.SYS first, and HCOS.SYS takes it if the drive holds an HDOS disk.
  An open HDOS file is described by a slot that the FCB points to, so the
  rest of the FCB keeps its CP/M meaning. CP/M records are halves of HDOS
  sectors.
- **Format detection.** A drive counts as HDOS-format when sector 9 holds
  a believable HDOS label.
- **Reading and writing HDOS disks.** Sectors go through the BIOS. HCOS
  follows HDOS's own structures (label, directory blocks, group reservation
  table) and allocation rules, so real HDOS can use the disks afterwards.
- **HDOS's directory on CP/M disks.** HDOS programs list directories by
  reading `DIRECT.SYS` and the group table. On a CP/M disk those are made
  up from the CP/M directory.

### C-mode and H-mode

HDOS was written for RAM starting at 2000H, below the ROMs, while CP/M
needs RAM at 0. The H89 can switch between the two with a port bit.

- **C-mode** is the default. HDOS programs get the HDOS system area at
  2000H, a working RST 7, and copies of the H17 ROM's utility routines at
  their ROM addresses. Most HDOS programs need nothing more.
- **H-mode** runs a program with the ROM switched in. Every SCALL switches
  RAM back in, does its work through the CP/M BIOS, and switches the ROM in
  again before returning. The switching code sits in a work area of the
  HDOS system area, because HCOS's own code is under the ROM.

## Ready-made disks

`disks/` has bootable HCOS disks, ready for an emulator or a real
machine:

- `hcos-full.h8d`: H17 (hard-sectored, 100K);
- `hcos37-full.h37`: H37 (soft-sectored), booted from the H37.

Each is Heath CP/M 2.2.03 with HCOS installed, plus `HDOS.COM`,
`ERRORMSG.SYS`, HDOS `BASIC.ABS` and `EDIT.ABS`. Type `BASIC` at the
`A>` prompt. `make hcos` rebuilds them.

## Installing on a disk

HCOS installs onto a copy of a **Heath CP/M 2.2.03 64K** disk, for the H17
or for the H17/H37, that still has its CP/M command processor:

```sh
make hcos      # builds the kernel; examples in build/disks/
python3 tools/sysgen.py MYCPM.h8d MYHCOS.h8d --base DA00 \
    --bdos build/kernel/h17/bdos.cim --ccp build/kernel/h17/hccp.cim
# (H17/H37 disks: --base D200 and build/kernel/h37/)
```

Then copy files onto the new disk with `h8dtool` (or `PIP` in HCOS):

- `HCOS.SYS` (`build/kernel/h17/HCOS.SYS` or `h37/HCOS.SYS`), so CP/M
  programs can use HDOS disks;
- `HDOS.COM` (`build/hdos.com`), to run HDOS programs;
- optionally `ERRORMSG.SYS` from an HDOS disk, for HDOS's error message
  texts;
- optionally an `HCOS.CFG`, for `ROMPROG` lines.

## Building and testing

Needs git, a C compiler, make and bison (the Xcode command line tools on
macOS), Python 3, and a built checkout of the
[H89 emulator](https://github.com/lesbird/H89) next to this repo (`../H89`)
or at `$H89_DIR`.

```sh
make tools   # build the pinned zmac assembler into tools/zmac/
make         # assemble everything into build/
make test    # make test disks and run all 60 emulator tests
make hcos    # build/disks/hcos.h8d and hcos37.h37: disks that boot HCOS,
             # and hcos-full.h8d and hcos37-full.h37 with HDOS.COM,
             # ERRORMSG.SYS, BASIC.ABS and EDIT.ABS added (copied to disks/)
```

The tests are mostly **differential**: the same program or keystrokes run
on the real operating system and on HCOS, and the output must match.

- `tests/difftest.sh` runs HDOS test programs (`tests/hdos/`) on real
  HDOS 2.0 and under HDOS.COM, on CP/M disks and on HDOS disks.
- `tests/cpmdiff.sh` runs CP/M test programs and sessions
  (`tests/cpm/*.asm`, `*.steps`) on Heath CP/M and on HCOS.
- `tests/run.sh` has scripted sessions, run on Heath CP/M and again on
  HCOS. They cover HDOS BASIC, PIP in both directions, real HDOS reading
  disks HCOS wrote, H-mode, the H37 and HDOS 3.0 calls.

A failing test leaves its final screen in `build/` for inspection.

## Limits

- **Memory and disks:** a 64K machine with Heath CP/M 2.2.03's layout is
  needed. HDOS disks are supported on drives A:–D:.
- **H8 front panel:** the H8 has not been tested. Its monitor (PAM-8),
  front panel and RAM-switching hardware differ from the H89's.
- **Device drivers:** HDOS loadable device drivers (`.DVD`, `.LOADD`) and
  programs that call the H17 ROM's disk routines directly (INIT, SYSGEN,
  TEST17) are not supported.
- **HDOS text** ends lines with LF only and isn't converted, so CP/M's
  TYPE shows it stepped.
- **STAT** on an HDOS disk gives the free space, capacity and directory
  size from the disk's own label, GRT and directory. A file over 16K is
  shown as 16K.
- **The date** for new HDOS files is fixed (01-Jan-80); CP/M has no clock.

## Project layout

| Path | Contents |
|---|---|
| `src/kernel/` | BDOS (`bdos.asm`, `kfs.asm`), HCCP (`hccp.asm`), HCOS.SYS (`kext.asm`, `kfb.asm`) |
| `src/hdoscom/` | HDOS.COM: SCALLs, console, files, the HDOS file system (shared with HCOS.SYS), the H17 ROM library |
| `src/inc/` | CP/M and HDOS interface definitions, shared layouts |
| `tools/` | `setup.sh` (zmac), `sysgen.py` (installs HCOS on a disk) |
| `tests/` | test programs, sessions and scripts |
| `docs/` | design and reference documents |

## Documents

- [Architecture](docs/ARCHITECTURE.md): the design and the roadmap
- [Kernel](docs/KERNEL.md): the BDOS, HCCP and HCOS.SYS
- [HDOS.COM](docs/HDOSCOM.md): the HDOS personality, H-mode
- [Research notes](docs/research-notes.txt): the first feasibility study

## Acknowledgements

- HDOS's interfaces come from the HDOS 3.0 sources and listings in
  [mgarlanger/asmx](https://github.com/mgarlanger/asmx), checked against
  real HDOS 2.0 running in the emulator.
- CP/M behaviour was matched by testing against Heath CP/M 2.2.03.
- Assembled with [zmac](http://48k.ca/zmac.html).
