# HCOS version 2

A from-scratch rewrite of HCOS for the Heathkit H89 (the H8 later). It
boots to its own prompt from a CP/M-format disk, with no Digital Research
or Heath CP/M code, and runs CP/M and HDOS programs natively: each kind
gets the memory map its own operating system gives it. CP/M programs get
Heath CP/M's 56K TPA.

Status: **phase 6 done**. HCOS v2 boots from an H17 or H37 disk with its
own boot record, BIOS, BDOS and shell, to an `A>` prompt 3.2 s after reset
from the H17 (Heath CP/M: 5.7 s). CP/M programs get Heath CP/M's 56K (54K
in the builds with an H37, whose driver is loaded at cold boot), and Heath's own
tools (ASM, DDT, ED, PIP, STAT, SUBMIT) give the same screens as on Heath
CP/M. CP/M programs can use HDOS disks: the first time one is used, HCOS
loads its HDOS file system (HDOSFS.COM) below the shell. HDOS programs
run natively, with the monitor ROM in at 0000H as on HDOS: type `BASIC`
and HDOS BASIC runs, through HDOS.COM in the RAM under the ROM.
The plan is [docs/PLAN.md](docs/PLAN.md), and the phase 0 research is in
[docs/research/](docs/research/).

Version 1, which runs on top of Heath CP/M, is the rest of this
repository and stays as it is.

## Layout

| Path | Contents |
|---|---|
| `docs/` | The plan, and the design notes as phases land |
| `src/` | Sources: `boot/` (boot records), `bios/`, `bdos/`, `shell/`, `hdoscom/` (HDOS.COM, and the HDOS file system it shares), `hdosx/` (the HDOS extension), `inc/` (the memory layout) |
| `tools/` | Host tools: `mksys.py` writes HCOS into a disk's reserved tracks |
| `tests/` | Emulator tests |

## Building

Needs what version 1 needs, including a built
[H89 emulator](https://github.com/lesbird/H89) at `../../H89` (or
`$H89_DIR`), whose Heath CP/M disk is the base for HCOS's.

```sh
make tools   # the pinned zmac assembler, shared with version 1
make         # the disks below
make test    # boot them in the emulator and check them
```

| Disk | Build | Boot with |
|---|---|---|
| `build/hcos.h8d` | H17 only, 56K | `h89run --disk0 build/hcos.h8d` |
| `build/hcos37.h8d` | H17 and H37 (D:-F:), 54K | `h89run --disk0 build/hcos37.h8d` |
| `build/hcos37.h37` | H37 and H17 (D:-F:), 54K | `h89run --sw501 30 --dk0 build/hcos37.h37` |

then `B` at the `H:` prompt. Each is a Heath CP/M disk (H17, or Heath's
H17/H37 disk) with HCOS in its reserved tracks.

`make test` runs:
- `tests/run.sh`: the BIOS on `build/test17.h8d`, whose test shell has
  disk tests (SUM, FILL, HALF, DIRW: see `src/shell/tshell.asm`), and
  the system on `build/hcos.h8d`;
- `tests/cpmdiff.sh`: CP/M programs and sessions (`tests/cpm/`) on
  Heath CP/M and on HCOS, which must give the same screens;
- `tests/difftest.sh`: HDOS programs (`tests/hdos/`) on real HDOS 2.0
  and on HCOS, which must print the same.
