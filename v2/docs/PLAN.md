# HCOS version 2: plan

- Status: **draft 0.2**, 2026-10-17. Nothing built yet.
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
the machine's ROM, which HDOS programs expect to find there. HCOS also uses
the ROM's disk routines at cold boot (section 5).

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

What's already known from version 1, and what has to be found out
(**[R]** = research item, section 8):

- **The memory switch:** the H89's ORG-0 bit in port 362Q (F2H) puts RAM
  at 0000H-1FFFH. Version 1's H-mode already switches it.
- **Console:** 8250 at 350Q (E8H) on the H89. Heath's BIOS also uses ports
  372Q/373Q (FAH/FBH) **[R]**.
- **Clock:** a 2 ms interrupt on RST 1. With the ROM in, the ROM takes it
  and passes it on through the vector at 201FH. With RAM in, the BIOS
  takes it at 0008H.
- **H17:** Heath's CP/M BIOS has its own driver on the controller ports
  174Q-177Q (7CH-7FH). It doesn't call the H17 ROM. HCOS's BIOS needs its
  own driver too, because the ROM isn't there while a CP/M program runs.
  The driver is timing-critical. Its models are the H17 ROM (444-19, in
  the H89 emulator's `roms/`) and Heath's BIOS **[R]**.
- **H37:** a WD1797 controller. Its model is Heath's H17/H37 BIOS **[R]**.
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
- **The BIOS** has 4K at F000H. Its jump table has the 17 CP/M 2.2 entries
  at F000H, so programs that call the BIOS directly keep working. The H17
  driver, the console, the clock and the buffers have to fit there.
  Heath's H17 BIOS does it in about the same space, with options HCOS
  doesn't need (CONFIGUR's I/O byte, printers).
- **H37:** Heath's H17/H37 BIOS needs 5.5K, and so Heath's H17/H37 CP/M
  has only a 54K TPA. HCOS tries to fit both drivers in 4K. If they don't
  fit, the H37 build gets its own BIOS base (as in version 1) and
  SYSGEN chooses by drive type.
- **The shell** is 2K at DA00H, like the CCP, so programs that keep the CCP
  (top of TPA = (0006H)-0806H) and return to it with RET work as on CP/M.
- **HDOS disks, from CP/M programs:** the HDOS file system (version 1's
  HCOS.SYS, about 4K) is an extension. It goes below the shell only while
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

1. The ROM's boot (MTR-90, H17 or H37) reads the boot record and jumps to
   it **[R1: what it loads, where, and how much]**.
2. **HCOS's boot record** runs with the ROM still in. It loads the system
   tracks and the BIOS, then switches RAM in and jumps to the BIOS's cold
   boot. At cold boot it can use the ROM's own disk-read routine
   **[R1, R2]**, so it needs no driver of its own.
3. The Heath H17 CP/M format reserves 3 tracks (7.5K). The boot record,
   shell and BDOS fit there (5.75K). The BIOS doesn't fit as well, so it goes
   in a file, `HCOS.SYS`, as Heath's goes in BIOS.SYS. SYSGEN writes a
   list of HCOS.SYS's sectors into the boot record, so the boot record
   needs no file system code. Keeping the reserved tracks as they are means
   HCOS disks are ordinary Heath CP/M disks to every other system.
4. **Warm boot** (^C, JMP 0, function 0) reloads the shell from the system
   tracks only if its checksum is wrong. The BDOS is reloaded only if *its*
   checksum is wrong. After a small program the prompt comes back with no
   disk access.

There's no date question. The date comes from the last `DATE` set,
saved on the boot disk, and HDOS programs see it in S.DATE.

**Speed:** about 10K to read, 4 tracks on the H17: 1-1.5 s from boot to
the prompt. To be measured in the emulator.

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
| 1 | Boot record and BIOS skeleton: cold boot from the system tracks and HCOS.SYS, console, clock, memory switch, a test program in place of the shell. A host tool (`v2/tools/`) makes the boot disk | own boot; boot time |
| 2 | The H17 driver in the BIOS: read and write, with retries. Checked by a sector test program and against `h8dtool` | own disk driver |
| 3 | Version 1's BDOS and a 2K shell on the new BIOS: a bootable HCOS disk. Heath's ED, PIP, STAT, ASM, LOAD, DDT and SUBMIT, with `cpmdiff.sh` against Heath CP/M. TPA measured | CP/M programs native, 56K |
| 4 | The HDOS extension for CP/M programs (version 1's HCOS.SYS moved across), loaded on demand | HDOS disks |
| 5 | HDOS programs natively: ROM in, system area, SCALLs, .LINK, .LOADO, ^C handlers. `difftest.sh` against real HDOS 2.0, BASIC | HDOS programs native |
| 6 | H37 driver | second controller |
| 7 | FORMAT, SYSGEN, DRIVES and DATE as programs. A disk HCOS makes boots HCOS | self-hosting |
| 8 | Sizes trimmed, ready-made disks in `v2/disks/`. Release 2.0 | |
| 9 | (later) The H8; the ideas in section 9 | |

## 8. Research before code (phase 0)

| # | Question | Where to look |
|---|---|---|
| R1 | What MTR-90's H17 and H37 boots read, where to and how much, what they leave set up, and whether a boot record can call the ROM's disk read routine | MTR-90 in the emulator's `roms/`, the emulator's source |
| R2 | How the H17 is read and written: sector sync, timing loops, checksums, step rate, motor, and use of the 2 ms clock | the H17 ROM (444-19), Heath CP/M's BIOS.SYS (disassembly), the SY driver source in asmx, if it is there |
| R3 | How the H37 is driven: 1797 commands, density, side select, which formats; how Heath's H37 system tracks are laid out | Heath's H17/H37 BIOS.SYS, the DK driver source in asmx, if it is there |
| R4 | The DPB for each Heath CP/M format to support, and how each is recognised. In version 1 HCOS used the BIOS's own and never needed them (V9) | Heath BIOS.SYS tables |
| R5 | The 8250, the other console ports, and what the ROM leaves set up | MTR-90, the emulator |
| R6 | How much of Heath's 4K BIOS is the H17 driver, and so how much room HCOS's BIOS will have | BIOS.SYS disassembly |
| R7 | Which real HDOS programs call the H17 ROM's disk routines directly (INIT, SYSGEN, TEST17), and whether they can run alongside the BIOS's driver (the drive's position can change under it) | tests |

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
| `bdos.asm` (CP/M 2.2, checked against DRI's) | Heath BIOS, with HCOS's | `sysgen.py` (Heath system tracks) |
| `hccp.asm`, cut down to the shell | HDOS.COM's `bios.asm` calls, with calls to HCOS's BIOS | `romlib.asm`, while the real ROM is in |
| `hdosfs`, `hdoswr`, `hdosdir`, `kfb`, `kxlib` (the HDOS extension) | H-mode's per-SCALL switching (no longer needed) | |
| `scall`, `console`, `files`, `sysarea`, `systab`, `syndir` (the SCALL layer) | | |
| The test harness and tests | | |
