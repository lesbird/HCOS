# HDOS.COM

HDOS.COM is a CP/M 2.2 program that runs HDOS 2.0 `.ABS` programs. They can
use files on CP/M disks and read and write real HDOS disks in the same
machine. It is
phases 1, 1b, 2 and 2b of HCOS. It proves the SCALL translation, the emulated
HDOS system area and the HDOS file system before they move into the HCOS
kernel.

```
A>HDOS [/T] PROG [args]
```

- `PROG` is an HDOS file name; the default type is `.ABS`. It can be on a
  CP/M disk or an HDOS disk (`HDOS SY1:BASIC`).
- `args` are passed to the program as HDOS's command processor passes them.
- `/T` traces every SCALL on the console as `[fff A=hh]`: the function in
  octal and A in hex.

Under HCOS you don't type `HDOS`: HCCP runs `NAME.ABS` through
`A:HDOS.COM` when there is no `NAME.COM` ([KERNEL.md](KERNEL.md)).

## What runs

Checked in the H89 emulator on Heath CP/M 2.2.03:

| Program | Status |
|---|---|
| BASIC.ABS (Benton Harbor BASIC #110.06.00) | Runs. RUN, SAVE, OLD, LIST, error messages and BYE all work. Covered by `make test`. |
| PIP.ABS | Copies files between CP/M disks and HDOS disks, either way. `/L` lists CP/M disks and HDOS disks, with sizes, dates, flags and free space. Covered by `make test`. |
| EDIT.ABS, PATCH.ABS, FLAGS.ABS | Start and take commands. Keystrokes so far behave the same as on real HDOS. |
| ONECOPY.ABS | Runs as far as asking for disks to be swapped. A single-drive copier doesn't fit under CP/M, which needs its system disk in A:. |
| SET.ABS | Exits with "Illegal Device Specification". It configures HDOS device drivers, which don't exist under CP/M. |

## Memory map

| Address | Contents |
|---|---|
| 0000H-00FFH | CP/M page zero. RST 1 and RST 7 are hooked while a program runs and put back on exit. |
| 0100H-182FH | HDOS.COM code and small data |
| 1830H-1991H | The H17 ROM utility library at its ROM addresses (`src/hdoscom/romlib.asm`) |
| 1992H-1FFFH | More code (the made-up directory), then small buffers and HDOS.COM's stack |
| 2000H-227FH | Emulated HDOS system area: monitor RAM cells, RST vector slots, S.VAL, S.INT. Command-line arguments sit just below 2280H. |
| 2280H-  | The HDOS program, as loaded from its header |
| BDOS−2.75K | HDOS.COM's high buffers: a GRT page for each of units 0-3, the scratch area (S.SCR), a directory block buffer, the type-ahead, the channel table and the command tail |
| BDOS-   | CP/M. S.SYSM is set to the start of the high buffers, so programs can use everything below them, including the CCP. On a 64K machine that is D500H, about 6K less than real HDOS 2.0 (EDB1H). |

## How it works

- **SCALL:** RST 7 goes to 0038H, then through the RAM slot at 2031H (as the
  HDOS ROM does) to the dispatcher in `scall.asm`. Handlers get the
  program's registers and run on HDOS.COM's own stack. The dispatcher also
  fills S.CACC and S.CODE as HDOS does.
- **Console** (`console.asm`) follows the HDOS 2.0 resident code (disassembled
  from HDOS.SYS):
  - Type-ahead, line editing and echo.
  - CR is stored as NL.
  - Rubout and ^U echo even when echo is suppressed.
  - ^O, ^S/^Q, and ^Z^Z abort.
  - ^A/^B/^C go to the program's `.CTLC` handlers. With no handler they are
    ignored.
  - Output does tab expansion, NL → CR LF, cursor tracking and wrapping.

  HDOS reads the keyboard on interrupts. HDOS.COM polls CP/M (BDOS 6)
  during every SCALL instead, so a ^C handler runs at the program's next
  SCALL.
- **Files** (`files.asm`):
  - Channels −1 to 5 each hold a CP/M FCB.
  - HDOS 256-byte sectors are two 128-byte records, accessed by random
    record number.
  - `.OPENW` writes `NAME.$$$` and replaces the old file at `.CLOSE`, so
    `.CLEAR`, or exiting without closing, leaves the old file alone, as on
    HDOS.
  - At the end of a CP/M file, half a sector reads as a whole sector with
    the second half zeroed.
  - The loaded program stays open on channel −1.
- **Devices:**
  - `SYn:` and `DKn:` map to drive n (A: = SY0:), units 0-3.
  - CP/M drive letters A:-D: are also accepted.
  - With no device and the default `SY0`, a file is on the current CP/M
    drive, and `.DECODE`/`.NAME` report that drive's unit.
  - `TT:` is the console and `LP:` the CP/M list device.
  - There are HDOS-style device and unit tables (S.DFWA, S.GUP) for
    programs that look at them, as PIP does.
- **HDOS disks** (`hdosfs.asm`, `bios.asm`):
  - A unit counts as an HDOS disk when it's an H17 drive (20 records a
    track in its DPB) and sector 9 holds a believable HDOS label.
  - Units are checked the first time a name on them is decoded, and again
    after any mount SCALL (`.MOUNT`, `.RESET`, ...). Those also make CP/M
    log its disks in again.
  - Sectors are read through the CP/M BIOS: HDOS sector n is track n/10,
    BIOS sectors 2(n mod 10)+1 and +2.
  - Files are found in the disk's own directory and read by following
    their GRT chains. DIRECT.SYS and GRT.SYS are ordinary files there.
  - Writing follows HDOS (`hdoswr.asm`, `hdosdir.asm`):
    - Groups come off the free chain at GRT[0].
    - `.OPENW` takes the first group at once and enters the file at
      `.CLOSE`, replacing an old file of that name.
    - `.CLEAR` gives a new file's groups back.
    - `.OPENU` writes over sectors in place and adds them at the end.
    - The GRT and the changed directory block are written back at each
      close, delete and rename.
    - Write-protected files give EC.WPV. `.OPENC` doesn't make the file
      contiguous.
  - Sector writes go through the BIOS. The second half of each sector is
    written as a "directory" write so the BIOS writes it at once.
- **Made-up directory for CP/M disks** (`syndir.asm`):
  - Opening DIRECT.SYS on a CP/M disk gives HDOS directory blocks built
    from the CP/M directory: 22 entries a block, names zero-padded.
  - CP/M's SYS attribute becomes the S flag (hidden from PIP without `/S`),
    and R/O becomes W.
  - The unit's GRT is filled in to match. Each file has a chain long enough
    for its size, and the free space is a chain on GRT[0]. PIP's sizes and
    free count come out right. The sectors per group are the smallest power
    of 2 that keeps the disk under 220 groups.
  - Dates show as No-Date.
- **Errors:** `.ERROR` reads `ERRORMSG.SYS` from the current drive, then A:,
  as HDOS reads it from SY0:. Copy it from an HDOS disk to get the messages.
  Without it you get "?02 Error # NNN".
- **ROM library:** Heath's programs call utility routines in the H17 ROM
  (`$TYPTX`, `$MOVE`, `$DADA`, `$MU86`, `$UDD`, ...). `romlib.asm` provides
  them at the same addresses. Its assembled bytes are identical to the 444-19
  ROM over that range.

## Not supported yet

- **`.LOADO`** succeeds, as on HDOS 3.0: everything is resident already.
  The overlay table says both overlays are resident.
- `.CHFLG`, `.DISMT` and `.LOADD` report themselves on the console and
  return EC.ILR.
- **Calls into resident HDOS through S.JUMPS** other than S.GUP. HDOS.COM
  names the entry point and exits.
- **HDOS 2.0 PIP quirks, matched on purpose:** it can't copy a file that
  has no extension (real HDOS gives "File Cannot Be Located" too).

  One deliberate difference: 2.0 PIP builds the name of the directory it
  lists with the unit as a binary byte ("SY\x01:DIRECT.SYS"). Real HDOS
  rejects that, so `PIP SY1:/L` fails there with "Device Format Error".
  HDOS.COM accepts it, so PIP can list any unit.
- **Programs that call the monitor ROM** (0000H-0FFFH), which is CP/M's
  page zero here. These need H-mode (phase 5).
- **Clock:** HDOS.COM counts ticks in .TICCNT. Program clock hooks (UO.CLK
  and the RST 1 slot) are not called, and S.TIME is not kept. The date is
  fixed at 01-Jan-80.
- **^C during a long computation:** HDOS delivers it from the clock
  interrupt. HDOS.COM delivers it only at the next SCALL.

## Testing

`tests/difftest.sh` runs each program in `tests/hdos/` on real HDOS 2.0 and
under HDOS.COM on CP/M, and compares the output between `{{` and `}}`.
A test marked `ALSO: hdos` (the file test) also runs under HDOS.COM with
its files on an HDOS disk, and must match real HDOS too. `tests/run.sh` has
scripted sessions: HDOS BASIC; PIP listing CP/M and HDOS disks; copying in
both directions; and real HDOS booting a disk HDOS.COM wrote to and running
the program copied onto it. Both run with `make test`.

HDOS.COM is now full: its code ends 18 bytes short of 2000H. Further work
goes into the HCOS kernel (phase 3 on).
