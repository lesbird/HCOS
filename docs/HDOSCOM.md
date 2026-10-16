# HDOS.COM

HDOS.COM is a CP/M 2.2 program that runs HDOS 2.0 `.ABS` programs. It is
phase 1 of HCOS. It proves the SCALL translation and the emulated HDOS
system area before both move into the HCOS kernel.

```
A>HDOS [/T] PROG [args]
```

- `PROG` is an HDOS file name; the default device and type are `SY0:` and
  `.ABS`.
- `args` are passed to the program as HDOS's command processor passes them.
- `/T` traces every SCALL on the console as `[fff A=hh]`: the function in
  octal and A in hex.

## What runs

Checked in the H89 emulator on Heath CP/M 2.2.03:

| Program | Status |
|---|---|
| BASIC.ABS (Benton Harbor BASIC #110.06.00) | Runs. RUN, SAVE, OLD, LIST, error messages and BYE all work. Covered by `make test`. |
| PIP.ABS | Copies files. `/L` (directory listing) stops: it calls S.GUP (see below). |
| EDIT.ABS, PATCH.ABS, FLAGS.ABS | Start and take commands. Keystrokes so far behave the same as on real HDOS. |
| ONECOPY.ABS | Stops: it needs `.LOADO` (overlays) and dismounts disks. |
| SET.ABS | Exits with "Illegal Device Specification". It configures HDOS device drivers, which don't exist under CP/M. |

## Memory map

| Address | Contents |
|---|---|
| 0000H-00FFH | CP/M page zero. RST 1 and RST 7 are hooked while a program runs and put back on exit. |
| 0100H-182FH | HDOS.COM code and small data |
| 1830H-1991H | The H17 ROM utility library at its ROM addresses (`src/hdoscom/romlib.asm`) |
| 1992H-1F07H | Buffers, scratch area (S.SCR) and HDOS.COM's stack (not stored in the .COM file) |
| 2000H-227FH | Emulated HDOS system area: monitor RAM cells, RST vector slots, S.VAL, S.INT. Command-line arguments sit just below 2280H. |
| 2280H-  | The HDOS program, as loaded from its header |
| BDOS-   | CP/M. S.SYSM is set to the BDOS page, so programs can use everything below it, including the CCP. |

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
  - `SYn:` and `DKn:` map to drive n (A: = SY0:).
  - CP/M drive letters are also accepted.
  - With no device and the default `SY0`, a file is on the current CP/M
    drive.
  - `TT:` is the console and `LP:` the CP/M list device.
- **Errors:** `.ERROR` reads `ERRORMSG.SYS` from the current drive, then A:,
  as HDOS reads it from SY0:. Copy it from an HDOS disk to get the messages.
  Without it you get "?02 Error # NNN".
- **ROM library:** Heath's programs call utility routines in the H17 ROM
  (`$TYPTX`, `$MOVE`, `$DADA`, `$MU86`, `$UDD`, ...). `romlib.asm` provides
  them at the same addresses. Its assembled bytes are identical to the 444-19
  ROM over that range.

## Not supported yet

- `.LOADO` (overlays), `.CHFLG`, `.DISMT` and `.LOADD` report themselves
  on the console and return EC.ILR. The mount calls (200Q and up) return
  EC.ILC.
- **Calls into resident HDOS through S.JUMPS** (S.GUP, S.FCI, ...). These are
  how PIP lists directories. HDOS.COM names the entry point and exits. This
  needs an HDOS view of the CP/M directory (phase 2).
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
`tests/run.sh` includes a scripted HDOS BASIC session. Both run with
`make test`.
