# HCOS — HDOS CP/M Operating System

A single operating system for the Heathkit H8 and H89 that runs both
**HDOS** (`.ABS`) and **CP/M 2.2** (`.COM`) programs, written in pure 8080
assembly.

Status: phases 1, 1b, 2, 2b and 3 done. **HCOS boots from disk** on its own
CP/M 2.2 BDOS ([KERNEL.md](docs/KERNEL.md)). **HDOS.COM** runs HDOS 2.0
`.ABS` programs, including HDOS BASIC and PIP, under HCOS or CP/M 2.2. They
can use CP/M disks and read and write real HDOS disks
([HDOSCOM.md](docs/HDOSCOM.md)).

- [Architecture](docs/ARCHITECTURE.md): the draft design
- [HDOS.COM](docs/HDOSCOM.md): phases 1-2b, HDOS programs under CP/M
- [Kernel](docs/KERNEL.md): phase 3, the HCOS BDOS and booting HCOS
- [Research notes](docs/research-notes.txt): feasibility research

## Building and testing

Needs git, a C compiler, make and bison (Xcode command line tools on
macOS), plus a built checkout of the
[H89 emulator](https://github.com/lesbird/H89) next to this repo (`../H89`)
or at `$H89_DIR`.

```sh
make tools   # build the pinned zmac assembler into tools/zmac/
make test    # assemble, make test disks, run every emulator test,
             # on Heath CP/M and on HCOS (build/hdos.com is HDOS.COM)
make hcos    # build/disks/hcos.h8d: a disk that boots HCOS
```

- Sources are 8080 assembly for zmac's 8080 mode (`-8`). A Z80-only
  instruction is an assembly error.
- `src/inc/` has the CP/M and HDOS interface definitions.
- `tests/mkdisks.sh` makes `build/disks/cpm.h8d` and `hdos.h8d` from the
  emulator's Heath boot disks.
- `tests/run.sh` boots each test disk headless with `h89run` and checks
  the screen. A failed test leaves its final screen in `build/test/`.
- `tests/difftest.sh` runs each `tests/hdos/*.asm` program on real HDOS 2.0
  and under HDOS.COM, and compares the output.
- `tests/cpmdiff.sh` runs each `tests/cpm/*.asm` program and `*.steps`
  session under Heath CP/M and under HCOS, and compares the output.
