# HCOS version 2

A from-scratch rewrite of HCOS for the Heathkit H89 (the H8 later). It
boots to its own prompt from a CP/M-format disk, with no Digital Research
or Heath CP/M code, and runs CP/M and HDOS programs natively: each kind
gets the memory map its own operating system gives it. CP/M programs get
Heath CP/M's 56K TPA.

Status: **planning** (phase 0). The plan is [docs/PLAN.md](docs/PLAN.md).

Version 1, which runs on top of Heath CP/M, is the rest of this
repository and stays as it is.

## Layout

| Path | Contents |
|---|---|
| `docs/` | The plan, and the design notes as phases land |
| `src/` | Sources: boot record, BIOS, BDOS, shell, extensions |
| `tools/` | Host tools, such as the boot disk maker |
| `tests/` | Emulator tests |

## Building

```sh
make tools   # the pinned zmac assembler, shared with version 1
make
```
