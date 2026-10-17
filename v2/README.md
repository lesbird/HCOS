# HCOS version 2

A from-scratch rewrite of HCOS for the Heathkit H89 (the H8 later). It
boots to its own prompt from a CP/M-format disk, with no Digital Research
or Heath CP/M code, and runs CP/M and HDOS programs natively: each kind
gets the memory map its own operating system gives it. CP/M programs get
Heath CP/M's 56K TPA.

Status: **phase 5 done**. HCOS v2 boots from an H17 disk with its own
boot record, BIOS, BDOS and shell, to an `A>` prompt 3.2 s after reset
(Heath CP/M: 5.7 s). CP/M programs get Heath CP/M's 56K, and Heath's own
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
make         # build/hcos.h8d: an H17 disk that boots HCOS v2
make test    # boot it in the emulator and check it
```

Boot it with `h89run --disk0 build/hcos.h8d`, then `B` at the `H:`
prompt. The disk is Heath CP/M's own (without CONFIGUR, MOVCPM17 and
ASM, for room), with HCOS in its reserved tracks.

`make test` runs:
- `tests/run.sh`: the BIOS on `build/test17.h8d`, whose test shell has
  disk tests (SUM, FILL, HALF, DIRW: see `src/shell/tshell.asm`), and
  the system on `build/hcos.h8d`;
- `tests/cpmdiff.sh`: CP/M programs and sessions (`tests/cpm/`) on
  Heath CP/M and on HCOS, which must give the same screens;
- `tests/difftest.sh`: HDOS programs (`tests/hdos/`) on real HDOS 2.0
  and on HCOS, which must print the same.
