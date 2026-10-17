# HCOS version 2

A from-scratch rewrite of HCOS for the Heathkit H89 (the H8 later). It
boots to its own prompt from a CP/M-format disk, with no Digital Research
or Heath CP/M code, and runs CP/M and HDOS programs natively: each kind
gets the memory map its own operating system gives it. CP/M programs get
Heath CP/M's 56K TPA.

Status: **phase 2 done**. HCOS v2 boots from an H17 disk on its own boot
record and BIOS, to a test shell, 2.2 s after reset (Heath CP/M: 5.7 s).
The BIOS has its own H17 driver and reads and writes CP/M and HDOS
disks.
The plan is [docs/PLAN.md](docs/PLAN.md), and the phase 0 research is in
[docs/research/](docs/research/).

Version 1, which runs on top of Heath CP/M, is the rest of this
repository and stays as it is.

## Layout

| Path | Contents |
|---|---|
| `docs/` | The plan, and the design notes as phases land |
| `src/` | Sources: `boot/` (boot records), `bios/`, `shell/`, `inc/` (the memory layout) |
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
prompt. The test shell knows VER, TIME and WAIT, and the disk tests
SUM, FILL, HALF and DIRW (see `src/shell/tshell.asm`).
