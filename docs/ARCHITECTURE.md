# HCOS Architecture

**HCOS** (HDOS CP/M Operating System): an operating system for the Heathkit H8 and H89 that runs both
**HDOS** (`.ABS`) and **CP/M 2.2** (`.COM`) programs, written in 8080 assembly.

- Status: **Draft 0.4**, 2026-10-16. Phases 1, 1b, 2 and 2b (HDOS.COM) and 3
  (the kernel's BDOS, booting from disk) are done; see
  [HDOSCOM.md](HDOSCOM.md) and [KERNEL.md](KERNEL.md).
- Background: [research-notes.txt](research-notes.txt)

> Facts marked **[VERIFY]** are from memory and must be checked against
> original documentation (HDOS 2.0 HOSDEF and the Programmer's Guide, the
> Heath CP/M BIOS listings, MTR-90 listings) before code depends on them.
> Section 12 collects them in one place.

---

## 1. Goals and non-goals

### Goals

1. Run unmodified CP/M 2.2 `.COM` programs that use only documented
   BDOS/BIOS interfaces.
2. Run unmodified HDOS 2.0 `.ABS` programs. HDOS 3.0 extensions come later.
3. Read and write both **CP/M-format** and **HDOS-format** disks, from
   either kind of program.
4. Run on an H89 (Z80) and on an H8 with an 8080A CPU and the ORG-0 option.
5. Leave a usable CP/M TPA of at least 44K on a 64K machine.

### Non-goals (version 1)

- Loadable HDOS device drivers (`.DVD`). Devices are built in.
- CP/M 3 / MP/M features (banking, multitasking).
- Bit-exact emulation of undocumented HDOS internals beyond what real
  test programs require.
- Z80-only code. **The kernel must assemble and run on an 8080.**

---

## 2. Hardware assumptions

| Item | H89 | H8 |
|---|---|---|
| CPU | Z80 (we use 8080 subset) | 8080A (or Z80 card) |
| Monitor ROM | MTR-88 / MTR-90 at 0000H | PAM-8 / XCON-8 at 0000H |
| ORG-0 (RAM at 0000H) | Built-in via port 362Q (F2H) **[VERIFY bit]** | Needs ORG-0 option, believed HA8-8 **[VERIFY]** |
| Console | 8250 serial at 350Q (E8H) **[VERIFY]** | H8-4 / H8-5 at 372Q (FAH) **[VERIFY]** |
| Clock | 2 ms tick on RST 1 **[VERIFY]** | Front-panel 2 ms tick on RST 1 |
| Disks | H17 (hard-sector, 5.25"), H37 (soft-sector, FD1797) | H17, H37 |
| RAM | 48K or 64K | 48K or 64K |

**The minimum supported configuration is 64K RAM with ORG-0 capability.**
48K support is a stretch goal.

---

## 3. Core idea: one kernel, two personalities

```
   +-------------------+       +-------------------+
   |  CP/M program     |       |  HDOS program     |
   |  (.COM @ 0100H)   |       |  (.ABS @ 2280H)   |
   +---------+---------+       +---------+---------+
             | CALL 0005H                | RST 7 + func byte
   +---------v---------+       +---------v---------+
   |  BDOS personality |       | SCALL personality |
   |  (FCB, 128-byte   |       | (channels, 256-   |
   |   records, '$')   |       |  byte xfers, b7)  |
   +---------+---------+       +---------+---------+
             +-------------+-------------+
                           |  kernel internal API (KAPI)
   +-----------------------v-----------------------+
   |                   KERNEL CORE                 |
   |  Loader | Memory/mode | Console | Error map   |
   |  Kernel File Block (KFB) layer                |
   |      +--------------+    +--------------+     |
   |      |  CP/M FS     |    |  HDOS FS     |     |
   |      +------+-------+    +------+-------+     |
   |  Deblocking buffer (256/512-byte sectors)     |
   +-------------------------+---------------------+
                             | BIOS-style driver table
   +-------------------------v---------------------+
   |  H17 driver | H37 driver | Console | LP | Clock |
   +-----------------------------------------------+
```

- **Personalities** only translate calling conventions, data formats and
  error codes. They hold no file system logic.
- **KAPI** is the single internal interface: register-based, carry set on
  error, A = HCOS error code. Both personalities call it.
- **File systems** sit behind a small vtable (open, close, read record,
  write record, delete, rename, search first/next, disk free). Each logical
  drive is bound to one file system when the drive is logged in.
- **Drivers** use a CP/M-BIOS-shaped jump table, so a standard CP/M BIOS
  entry vector can also be exposed at the address in 0001H. Programs that
  call the BIOS directly (e.g. `CONOUT` via `(0001H)+9`) keep working.

---

## 4. Memory map (64K)

The resident kernel is in high memory and is identical in every mode.
What changes is the bottom 8K.

```
Address   C-mode (CP/M rules)          H-mode (HDOS rules)
--------  ---------------------------  ------------------------------
0000H     Page zero (RAM)              Monitor ROM (MTR/PAM)
          0000 JMP WBOOT  0005 JMP BDOS
          0008 RST1 -> clock handler
          0038 RST7 -> SCALL handler*
005CH     Default FCB 1 / 006C FCB 2
0080H     Default DMA / command tail
0100H     CP/M TPA start               ROM / H17 work RAM (1400H) /
  ...                                  H17 ROM (1800H)  [H89]
2000H     (TPA, or HDOS sys area*)     HDOS system area (emulated)
2280H     (TPA, or HDOS program*)      HDOS program load address
  ...
C000H     -------- HCOS resident kernel (budget 16K, target 12K) --------
          BDOS entry stub (address stored at 0006H)
          SCALL dispatcher
          KAPI, loader, KFB layer, file systems, deblock buffers
          Driver jump table (BIOS vector, address in 0001H)
          Kernel stack
FFFFH
```

\* C-mode can also host HDOS programs. See section 5.

**Size budget (initial estimates, to be updated as code lands):**

| Component | Est. size |
|---|---|
| BDOS personality | 1.5K |
| SCALL personality | 2.0K |
| KAPI + KFB layer + loader | 1.5K |
| CP/M FS | 2.0K |
| HDOS FS | 2.0K |
| H17 + H37 drivers | 2.0K |
| Console / LP / clock | 0.5K |
| Command processor (transient, reloaded on exit) | 2.0K |
| Buffers (2 x 512 sector + dirs) | 1.5K |
| **Total resident** | **~11-13K** |

The command processor is **transient**, like the CP/M CCP: it is overwritten
by programs and reloaded from disk on warm boot. This keeps the resident
size down.

---

## 5. Execution modes

### C-mode: RAM at 0000H

Used for **all CP/M programs and, by default, HDOS programs too**.

HDOS programs load at 2280H. They need the 2000H-227FH system area, a
working RST 7, and, it turns out, the H17 ROM's utility library. All of that
can live in RAM. In C-mode the kernel:

1. Builds page zero. `0038H` holds a JMP to the RST 7 RAM slot.
2. Builds the emulated HDOS system area at 2000H-227FH (laid out in
   `src/inc/hdos.inc`, checked against a dump of HDOS 2.0).
3. **Recreates the ROM's vector indirection.** RST n jumps through the RAM
   slot at `.UIVEC+3*(n-1)` (201FH; RST 7 is 2031H), as the real ROM does.
   HDOS programs that patch those vectors then behave as on real HDOS.
4. **Provides the H17 ROM utility library at 1830H-1991H.** Heath's own
   programs call `$TYPTX`, `$MOVE`, `$DADA`, `$MU86`, `$UDD` and others at
   their ROM addresses (HDOS BASIC fails without them). The kernel keeps
   that range free and puts an exact copy of the routines there
   (`src/hdoscom/romlib.asm`).
5. Points S.SCR (2151H) at a 512-byte scratch area. BASIC uses it.

This means most HDOS programs never need a memory-mode switch. Only programs
that call the monitor ROM (0000H-0FFFH, which is page zero in C-mode) or the
H17 ROM's disk routines need H-mode.

### H-mode: ROM at 0000H

Used only for HDOS programs that **call monitor ROM routines or the H17
ROM's disk routines directly**, or read ROM contents. The H17 ROM's utility
library is provided in C-mode (section 5). Programs are routed to H-mode by a
compatibility list (`HCOS.CFG`, see section 9) or a command flag
(`RUN /ROM PROG`).

In H-mode:

- RST 7 enters the ROM at 0038H, which vectors through 20xxH into the kernel's
  SCALL dispatcher.
- The clock interrupt arrives through the ROM vector.
- Kernel disk drivers still do all disk I/O. ROM disk routines are not used.
  This keeps one driver code path.

### Switching modes

The switch is performed only by the kernel, at program load and program exit:

```
LOAD:  disable interrupts
       select mode (write ORG-0 bit on H89 port 362Q; H8 equivalent)
       build page zero (C-mode) or check ROM vectors (H-mode)
       build HDOS system area if .ABS
       set SP, enable interrupts, jump to entry
EXIT:  any exit path -> kernel -> force C-mode -> reload command processor
```

The kernel itself is above C000H, so it is unaffected by the switch. Any
code that runs during the switch must live in the kernel region.

---

## 6. Program loading and exit

| File type | Detection | Load | Entry |
|---|---|---|---|
| `.COM` | extension | raw image at 0100H, up to kernel base | 0100H |
| `.ABS` | extension, plus header bytes 377Q, 000Q | header gives load address and length | header entry address |

`.ABS` header (8 bytes): `377Q`, type `000Q`, load address (2), length (2),
entry address (2). Checked against every `.ABS` on the HDOS 2.0 system disk.
Most load at 2280H; `INIT.ABS` loads at 2480H, so the loader must honour the
header. Length counts only the image, not the header.

Heath listings write addresses in split octal (high byte.low byte): 2280H
is `042.200`, which is **not** `042200Q` (that is 4480H).

**Exit paths, all of which return to the kernel:**

| Path | Personality | Notes |
|---|---|---|
| `JMP 0000H` / RST 0 | CP/M | warm boot |
| BDOS function 0 | CP/M | |
| `RET` to the CCP stack | CP/M | loader pushes a return address to the kernel |
| `SCALL .EXIT` | HDOS | |
| Ctrl-C abort | both | HDOS honours `.CTLC` handlers first |

On exit the kernel closes all HDOS channels and flushes dirty buffers. It
does **not** auto-close CP/M FCBs, because CP/M programs routinely skip closing
files they only read.

---

## 7. File layer: the Kernel File Block (KFB)

The central design choice is that **all open files are described by a
36-byte Kernel File Block that has the same shape as a CP/M FCB.**

```
KFB offset  CP/M meaning          HCOS use
  0         drive                 drive (0 = default, 1..16)
  1-8       name                  name
  9-11      type (+attr bits)     extension
  12        EX                    extent / FS-defined
  13-14     S1,S2                 S2 = module; S1 = HCOS signature/FS tag
  15        RC                    record count / FS-defined
  16-31     allocation map        FS-PRIVATE AREA (16 bytes)
  32        CR                    current record
  33-35     R0-R2                 random record number
```

- **On CP/M-format disks** the FS-private area *is* the CP/M allocation
  map. BDOS semantics are native, and programs that keep, copy or poke FCBs
  work as they do on real CP/M.
- **On HDOS-format disks** the FS-private area holds the HDOS locator:
  directory position, first group, current group, sector in group, last
  group and last-sector index. The CP/M program never looks inside it, so
  it works unchanged. A CP/M program can therefore open a file on an HDOS
  disk through an ordinary FCB, with no handle table and nothing to leak.
- **HDOS channels** are a fixed table of 7 slots (channels -1..5 **[VERIFY]**).
  Each slot *contains* a KFB, so an HDOS program can open files on CP/M disks
  through the same code.

### Record size

The kernel's logical unit is the **128-byte record**.

- An HDOS `.READ` / `.WRITE` of N x 256 bytes is converted to 2N records.
- HDOS end-of-file is at a 256-byte sector boundary. A CP/M program reading
  an HDOS file sees whole sectors and no Ctrl-Z padding.
- A shared deblocking buffer handles 256-byte (H17) and 512-byte (H37)
  physical sectors.

### File name translation

| Input | Resolves to |
|---|---|
| `B:FOO.TXT` (CP/M) | logical drive 2 |
| `SY1:FOO.TXT` (HDOS) | logical drive 2 |
| `DK0:` (HDOS) | logical drive mapped in `HCOS.CFG` |

One drive table maps `A:`=`SY0:`, `B:`=`SY1:`, `C:`=`SY2:` by default.
HDOS default-extension blocks (the `DE` argument to `.OPENR`) are applied
in the SCALL personality before the name reaches KAPI.

### Text files

No translation is done by default. Text conversion (HDOS has no Ctrl-Z
convention, CP/M does) is left to utilities. **Open question:** should
reading an HDOS-disk file through BDOS return a synthetic Ctrl-Z at EOF
when the file has a text extension?

---

## 8. File systems

### 8.1 CP/M FS

Standard CP/M 2.2 directory and allocation with a disk parameter block per
format. DPBs come from the Heath/Zenith CP/M BIOS for:

- H17 SS 40-track (10 x 256-byte hard sectors per track)
- H17 DS / 80-track variants
- H37 formats

**[VERIFY all DPB values from BIOS listings]**

### 8.2 HDOS FS **[VERIFY all structure details]**

- H17 disk: 40 tracks x 10 sectors x 256 bytes = 400 sectors (100K, SS).
- Allocation in **groups** of sectors; group size depends on the media.
- `GRT.SYS`: group reservation table, one byte per group linking the chain.
- `DIRECT.SYS`: fixed-size directory entries with name, ext, flags, cluster
  factor, first and last group, last-sector index, and dates.
- Disk label sector with volume serial number and parameters.

**Format detection** happens at drive login. Read the label/boot area and
check for an HDOS volume signature. If it is absent, fall back to the CP/M
DPB guess for that drive type. The result is cached in the drive table
until the next reset or disk change.

---

## 9. Configuration: `HCOS.CFG`

A small text file read at cold boot:

```
DRIVE A H17 0
DRIVE B H17 1
DRIVE C H37 0
ROMPROG PIE.ABS        ; run in H-mode
ROMPROG XYZ.ABS
CONSOLE BAUD 9600
```

---

## 10. Personality details

### 10.1 BDOS personality (CP/M 2.2)

All 0-40 BDOS functions. Functions 1-12 (console) map directly. Functions
13-40 (disk) translate to KAPI calls on the caller's FCB, which is used
directly as the KFB. The BIOS vector at `(0001H)` points at the driver jump
table.

### 10.2 SCALL personality (HDOS 2.0)

Dispatcher on RST 7: pop the return address, fetch the inline function byte,
skip it, then index a dispatch table. Errors return with carry set and A set
to the HDOS error code (via the error map).

Initial SCALL table **[VERIFY numbers against HOSDEF; rows marked checked ran on real HDOS 2.0]**:

| Octal | Name | Version 1 | Maps to |
|---|---|---|---|
| 000 | `.EXIT` | yes | kernel exit (checked) |
| 001 | `.SCIN` | yes | console status/read (no wait) |
| 002 | `.SCOUT` | yes | console out |
| 003 | `.PRINT` | yes | print from HL until a char with bit 7 set (checked) |
| 004 | `.READ` | yes | KFB read N x 256 |
| 005 | `.WRITE` | yes | KFB write N x 256 |
| 006 | `.CONSL` | yes | console mode bytes in sys area |
| 007 | `.CLRCO` | yes | flush console input |
| 010 | `.LOADO` | later | overlay load |
| 011 | `.VERS` | yes | report HDOS version (2.0) |
| 040 | `.LINK` | yes | chain to program |
| 041 | `.CTLC` | yes | register Ctrl-A/B/C handlers |
| 042 | `.OPENR` | yes | open read |
| 043 | `.OPENW` | yes | open write |
| 044 | `.OPENU` | yes | open update |
| 045 | `.OPENC` | yes | open contiguous |
| 046 | `.CLOSE` | yes | close |
| 047 | `.POSIT` | yes | position (sector) |
| 050 | `.DELET` | yes | delete |
| 051 | `.RENAM` | yes | rename |
| 052 | `.SETTP` | yes | set top of memory |
| 053 | `.DECODE` | yes | parse file name |
| 054 | `.NAME` | yes | get channel's file name |
| 055 | `.CLEAR` | yes | clear channel |
| 056 | `.CLEARA` | yes | clear all channels |
| 057 | `.ERROR` | yes | print error message |
| 060 | `.CHFLG` | later | change file flags |
| 061 | `.DISMT` | later | dismount |
| 062 | `.LOADD` | no | loadable device driver (deferred) |
| 200+ | system calls (`.MOUNT` etc.) | later | |

### 10.3 Emulated HDOS system area (2000H-227FH)

This is populated before every `.ABS` launch. It includes the RAM RST vector
slots, console mode bytes, top-of-memory and system memory pointers, the
date, S.SCR, and S.JUMPS. The layout, with its sources, is in
`src/inc/hdos.inc`. It was checked against a memory dump of HDOS 2.0 in
the emulator and against the HDOS 3.0 decks.

Programs poke these cells directly (EDIT writes S.CSLMD, SYSCMD writes
S.CUSOR), so the console code keeps its state in them rather than in
private variables.

### 10.4 What phase 1 established

Real HDOS 2.0 behaviour that the kernel must copy, all covered by
differential tests (`tests/hdos/`):

- `.VERS` returns 20H. Programs check it.
- Command-line arguments are uppercased, NUL-terminated, and end at 227FH.
  SP points at them.
- `.OPENW` replaces the old file only at `.CLOSE`. `.EXIT` does `.CLEARA`,
  so unclosed writes are discarded.
- `.LINK` keeps SP and A, clears the ^A/^B/^C handlers, and leaves the file
  open on channel −1.
- ^A/^B/^C with no handler are ignored, not an abort. Handlers run when the
  current SCALL returns, with A = 1 and a resume address on the stack.
- CR is stored as NL. Rubout and ^U echo even with echo suppressed.
- A `.READ` that hits the end returns EC.EOF with BC = the count not read.

---

## 11. Command processor (`HCCP`)

A transient command processor that accepts both styles:

```
A>DIR B:*.ASM          (CP/M style)
A>CAT SY1:             (HDOS-style alias)
A>PIP B:=A:*.COM
A>MBASIC               searches .COM, then .ABS
A>RUN /ROM PIE         force H-mode
```

Built-ins: `DIR`/`CAT`, `TYPE`, `ERA`/`DELETE`, `REN`/`RENAME`, `USER`,
`SAVE`, `DRIVES` (show drive-to-FS bindings), `MODE` (show or set console).

The search order for a bare program name is `.COM`, then `.ABS`. This can
be changed in `HCOS.CFG`.

---

## 12. Open questions and verification list

| # | Item | Source to check |
|---|---|---|
| V1 | H89 ORG-0 port/bit (MTRRAM: CB2.ORG = 20H in OP2.CTL); H8 ORG-0 hardware | H89 manual, Heath CP/M BIOS |
| ~~V2~~ | ROM RST vector routing: **done**, `.UIVEC` = 201FH, RST 7 slot 2031H | HDOS 2.0 dump, HDOS 3.0 source |
| ~~V3~~ | HDOS system area layout: **done**, `src/inc/hdos.inc` | HDOS 2.0 dump, ESVAL/ESINT/HOSEQU |
| ~~V4~~ | SCALL numbers and conventions: **done** for every call HDOS.COM implements | HOSDEF, HDOS 3.0 listing, HDOS 2.0 disassembly, differential tests |
| ~~V5~~ | `.ABS` header format: **done**, see section 6 | HDOS 2.0 system disk |
| ~~V6~~ | HDOS directory, GRT, RGT and label format: **done**, `src/hdoscom/hdosfs.asm` | DIRDEF, DISDEF, LABDEF, HDOS 2.0 disk image |
| ~~V7~~ | Channels: **done**, −1 to 5 (−1 = loaded program) | HDOS 3.0 listing, tests |
| ~~V8~~ | Error codes: **done**, `src/inc/hdos.inc` | ECDEF |
| V9 | CP/M DPBs for H17/H37 formats | Heath CP/M BIOS |
| V10 | Console and clock port addresses | H8/H89 manuals |
| Q1 | Synthetic Ctrl-Z for HDOS text files read via BDOS? | design decision |
| Q2 | Support 48K machines? | depends on measured size |
| ~~Q3~~ | Assembler: **zmac** in 8080 mode (`-8`), which rejects Z80-only opcodes. Hex by default, octal `Q` where Heath documents use octal | decided |

---

## 13. Development roadmap

| Phase | Deliverable | Proves |
|---|---|---|
| 0 | **Done.** Toolchain, emulator setup ([lesbird/H89](https://github.com/lesbird/H89)), test disk images, build script | can build and boot |
| 1 | **Done.** **`HDOS.COM`** runs `.ABS` files under stock CP/M (C-mode, SCALL at 0038H, console and file SCALLs mapped to BDOS). HDOS BASIC runs. See [HDOSCOM.md](HDOSCOM.md) | SCALL translation, sys area |
| 1b | **Done.** `.LOADO`, device/unit tables and S.GUP, a made-up DIRECT.SYS and GRT for CP/M disks: PIP lists CP/M disks | more of Heath's utilities |
| 2 | **Done.** HDOS FS read-only module inside `HDOS.COM` (raw BIOS sector access): run, copy and list from real HDOS disks | HDOS on-disk format |
| 2b | **Done.** Writing HDOS disks (GRT allocation, directory update) | full HDOS FS |
| 3 | **Done** (see [KERNEL.md](KERNEL.md)). HCOS boots from disk on its own CP/M 2.2 BDOS, installed in the system tracks; drivers are the Heath BIOS. CP/M's own tools and all HDOS.COM tests pass on it | replaces CP/M |
| 4 | SCALL personality moved into the kernel; HDOS FS read/write; HCCP | dual personality |
| 5 | H-mode (ROM swap) + `ROMPROG` list | ROM-dependent programs |
| 6 | H37 driver, HDOS 3.0 SCALLs, `.LOADO` overlays | broader compatibility |
| 7 | (optional) `.DVD` loadable driver support | full HDOS parity |

**References found so far:** HDOS 3.0 source and include decks, with
assembled listings of HDOS, PIP, SYSCMD, EDIT and others, are in
[mgarlanger/asmx](https://github.com/mgarlanger/asmx) (`testHdos/`).
`acm2/` there has the HDOS 2.0 versions of the decks.

**Test corpus** (to be assembled from SEBHC archives): MBASIC (both
versions), the HDOS assembler and `PIE`, `ONECOPY`/`PIP`, Microsoft
Fortran, WordStar (CP/M), Turbo Pascal 3 (CP/M, 8080 version if
available), and games from both libraries.
