# HCOS 2.0

An operating system for the Heathkit H89 that runs **both** of the
machine's software libraries, each the way its own system ran it:

- **CP/M 2.2 programs** (`.COM`) get RAM at 0000H, page zero, a BDOS and
  a BIOS, and **Heath CP/M's 56K** (54K with an H37).
- **HDOS 2.0 programs** (`.ABS`) get the monitor ROM and H17 ROM at
  0000H, the HDOS system area at 2000H and SCALLs on RST 7, as on HDOS.

Either kind can use **CP/M and HDOS disks**, on the H17 and the H37.
HCOS boots from a CP/M-format disk to its own `A>` prompt. It is written
from scratch in 8080 assembly. It uses no Digital Research or Heath CP/M
code: its own boot records, BIOS, BDOS and shell. It uses the machine's
ROM only to boot and where HDOS programs expect it.

Version 1, which ran on top of Heath CP/M, is the rest of this
repository. How version 2 was designed and built is in
[docs/PLAN.md](docs/PLAN.md), and the hardware research behind it is in
[docs/research/](docs/research/).

## Ready-made disks

| Disk | For | Boots from | Drives | CP/M TPA |
|---|---|---|---|---|
| [`disks/hcos-h17.h8d`](disks/) | an H89 with an H17 | H17 | A:-C: H17 | 56K |
| [`disks/hcos-h17x.h8d`](disks/) | an H17 and an H37 | H17 | A:-C: H17, D:-F: H37 | 54K |
| [`disks/hcos-h37.h37`](disks/) | an H37 and an H17 | H37 | A:-C: H37, D:-F: H17 | 54K |

All three need 64K. Each is a Heath CP/M disk with HCOS in its reserved
tracks. Besides Heath's ASSIGN, DDT, ED, LOAD, PIP, STAT, SUBMIT and XSUB,
each holds HCOS's own programs (below), HDOS.COM, HDOSFS.COM, and HDOS
BASIC and EDIT. The disks with two controllers load the second driver
(H37.COM or H17.COM) by themselves at cold boot, when SW501 says that
controller is fitted.

In the [H89 emulator](https://github.com/lesbird/H89):

```sh
h89run --disk0 disks/hcos-h17.h8d             # then B at the H: prompt
h89run --disk0 disks/hcos-h17x.h8d --dk0 MY.H37
h89run --sw501 30 --dk0 disks/hcos-h37.h37    # (SW501 30: boot from the H37)
```

```
H: Boot
HCOS 2.0
A>BASIC
Extended Benton Harbor BASIC #110.06.00
*PRINT PEEK(0)
 195
```

The prompt is up 3.2 s after reset from the H17 (Heath CP/M takes 5.7 s)
and 8.6 s from the H37 (Heath's H37 CP/M takes 15.5 s).

## Using it

**CP/M programs** run as on CP/M: `STAT`, `PIP B:=A:*.COM`, `DDT`,
`SUBMIT`. The shell has CP/M's built-in commands (DIR, ERA, REN, SAVE,
TYPE, USER), with CAT as DIR. Heath's ASM, DDT, ED, PIP, STAT and SUBMIT
give the same screens as on Heath CP/M.

**HDOS programs** run by name: `BASIC` finds BASIC.COM, then BASIC.ABS.
`HDOS PIP` runs HDOS's own PIP (a CP/M PIP.COM is found first otherwise).
In HDOS programs, SY0:-SY3: are A:-D:. HDOS console handling, ^C
handlers, `.LINK`, overlays and error messages behave as on HDOS 2.0, and
programs that call the ROM's routines or read the ROM work.

**HDOS disks from CP/M programs:** the first time a CP/M program meets an
HDOS disk, HCOS says `Bdos Err On B: Select`. It then loads its HDOS file
system at the next warm boot (`HDOS disks: HDOSFS loaded`). From then on,
DIR, PIP, ERA, REN, STAT and other programs use the HDOS disk like any
other, with the TPA 7K smaller, until the next cold boot.

**HCOS's own programs:**

| Command | What it does |
|---|---|
| `FORMAT d:` | formats the disk in d: (not A:) for CP/M |
| `FORMAT d: HDOS` | makes it an HDOS 2.0 data disk, as HDOS INIT would |
| `SYSGEN d:` | puts HCOS on d:, a disk on the same controller as A: |
| `DATE [dd-Mmm-yy]` | shows or sets the date HDOS programs and new HDOS files get (the H89 has no clock; it is kept in HDOS.COM and HDOSFS.COM on A:) |
| `DRIVES` | lists each drive's controller and what's in it |
| `H37`, `H17` | loads the second controller's driver (done at cold boot) |

Heath's own FORMAT, SYSGEN and DUP are left off: they call into Heath's
BIOS.

## Limits

- **Disk formats:** single-sided, single-density, 40 tracks of 10 x 256
  bytes (the H17's format, and Heath's H37 format 0). Two-sided and
  double-density H37 disks, and 80 tracks, are not supported yet.
- **Tested in the emulator only.** Every timing constant is Heath's
  (step rate, motor start, settle), and the H17 driver keeps the ROM's
  byte timing. But the emulator doesn't model step rates, motor spin-up,
  head settling or missed bytes, so the first runs on a real H89 are the
  real test.
- **HDOS programs that drive the disk through the ROM** (INIT, HDOS
  SYSGEN, TEST17) and HDOS loadable device drivers (`.DVD`) don't work.
  `FORMAT d: HDOS` does INIT's job.
- **HDOS programs** see drives A:-D: only, and get 2280H-D5FFH (2K less
  in the H37 builds; real HDOS 2.0 gives up to EDB0H).
- **The H8** isn't supported yet (its monitor, console and memory switch
  differ).

## Building and testing

Needs git, a C compiler, make and bison (for the zmac assembler), Python
3, and a built [H89 emulator](https://github.com/lesbird/H89) checkout at
`../../H89` (or `$H89_DIR`). Its Heath CP/M and HDOS disks are the base
for HCOS's.

```sh
make tools     # the pinned zmac assembler, shared with version 1
make           # build/: the three system disks, and the test disks
make test      # 81 emulator tests
make release   # disks/: the ready-made disks
```

`make test` runs:

- `tests/run.sh`: 63 scripted sessions. They cover the BIOS (disk
  driver tests on `build/test17.h8d`, through its test shell), the
  system, HDOS disks, HDOS programs, the H37, booting from it, and
  FORMAT, SYSGEN, DATE and DRIVES. Disks are checked byte for byte on the
  host, and real HDOS 2.0 must read the HDOS disks HCOS writes and
  formats.
- `tests/cpmdiff.sh`: CP/M programs and sessions (`tests/cpm/`) on Heath
  CP/M and on HCOS. The screens must be the same.
- `tests/difftest.sh`: HDOS programs (`tests/hdos/`) on real HDOS 2.0 and
  on HCOS. They must print the same.

## Layout

| Path | Contents |
|---|---|
| `src/boot/` | the H17 and H37 boot records |
| `src/bios/` | the BIOS, the H17 and H37 drivers, the slot loaders (H17.COM, H37.COM) |
| `src/bdos/` | the BDOS: CP/M 2.2's calls, its file system, the hook for HDOS disks |
| `src/shell/` | the shell (a CP/M 2.2 CCP that also runs .ABS programs), and the test shell |
| `src/hdoscom/` | HDOS.COM: SCALLs, the HDOS system area, console, files, and the HDOS file system |
| `src/hdosx/` | HDOSFS.COM: the HDOS file system for CP/M programs |
| `src/util/` | FORMAT, SYSGEN, DATE, DRIVES |
| `src/inc/` | the memory layout (`layout.inc`) and the CP/M and HDOS definitions |
| `tools/mksys.py` | writes HCOS into a disk's reserved tracks |
| `tests/` | the emulator tests |
| `disks/` | the ready-made disks |
| `docs/` | the plan and the research |

Memory, in the H17 build (the H37 builds are 2K lower from the shell
up):

| Address | CP/M program | HDOS program |
|---|---|---|
| 0000H | page zero, then the TPA | the ROM (HDOS.COM in the RAM under it) |
| 2000H | | the HDOS system area, then the program from 2280H |
| C300H | (the HDOS file system, when it is loaded) | |
| D600H | | HDOS.COM's buffers and tables |
| DA00H | the shell (2K, reloaded if a program overwrites it) | |
| E200H | the BDOS (entry E206H) | |
| F000H | the BIOS: drivers, buffers (and in the H37 builds the second driver's slot) | |
