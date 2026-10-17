# The HCOS kernel

HCOS boots from disk and runs **both CP/M and HDOS programs**. Its parts,
all in `src/kernel/`, are written from the CP/M 2.2 and HDOS interfaces
and contain no DRI code:

| Part | Where | Phase |
|---|---|---|
| **BDOS**: CP/M 2.2 file system and console | system tracks, E200H | 3 |
| **HCCP**: the command processor | system tracks, DA00H | 4 |
| **HCOS.SYS**: kernel extension, the HDOS file system for CP/M programs | file, loaded to C300H | 4 |
| **HDOS.COM**: HDOS personality (SCALLs), loaded when an `.ABS` runs | file | 1-2b |

```sh
make hcos      # build/disks/hcos.h8d (H17) and hcos37.h37 (H17/H37)
python3 tools/sysgen.py YOUR.h8d OUT.h8d --base DA00 \
    --bdos build/kernel/h17/bdos.cim --ccp build/kernel/h17/hccp.cim
               # then copy HCOS.SYS and HDOS.COM on
```

**Targets.** Every address follows from the BIOS base in the build's
`target.inc` (`src/inc/hcos.inc`):

| Target | Heath CP/M | BIOS | BDOS | HCCP | HCOS.SYS |
|---|---|---|---|---|---|
| h17 | 64K for the H17 | F000H | E200H | DA00H | C300H |
| h37 | 64K for the H17 and H37 | E800H | DA00H | D200H | BB00H |

`sysgen.py` finds the CCP in the system tracks by DRI's copyright line.
The two disk layouts differ (offset 80H on H17 disks, 100H on H37 disks).
It checks that the CCP's address matches `--base`. It takes `.h8d` and
single-density `.h37` images.

On an HCOS disk:

```
A>BASIC                 runs BASIC.COM, or else BASIC.ABS (through HDOS.COM)
A>PIP A:=B:*.ABS[OV]    CP/M PIP copying from an HDOS disk in B:
A>DIR B:                lists it (CAT does the same)
```

## How it boots

The Heath H17 boot path, worked out from the disk and from memory dumps
of the running system:

1. **The monitor ROM** reads 1E00H bytes from the start of the disk to
   D980H. That covers:
   - the boot record (D980H);
   - the CCP (DA00H);
   - the BDOS (E200H);
   - a small *loader BIOS* (F000H).
2. **The loader BIOS's cold boot** sets up page zero and calls the BDOS:
   function 13, then 15 to open `BIOS.SYS`, then 26 and 20 to read it.
   `BIOS.SYS` is a 256-byte header followed by the BIOS assembled at 0000H,
   so only high bytes are relocated. It is relocated to F000H. **So the
   HCOS BDOS already loads the real BIOS.**
3. **The real BIOS's warm boot** reloads 44 records (D980H–EF7FH: the CCP
   and BDOS) from the system tracks. It points 0005H at E206H and enters
   the CCP at DA00H or DA03H. Bits 7 and 6 of the BIOS byte at F036H choose
   auto-start of the CCP's command on cold and warm boot (CONFIGUR).

`tools/sysgen.py` writes the HCOS BDOS at disk offset 880H, the bytes
loaded to E200H, and zeroes the rest up to EF7FH. The DRI CCP compares the
6-byte serial number at the start of the BDOS with its own and halts if
they differ, so sysgen copies it from the BDOS it replaces.

## Memory (64K)

| Address | Contents |
|---|---|
| 0100H-C2FFH | TPA (48.75K; 56K if there is no HCOS.SYS) |
| C300H-D8FFH | HCOS.SYS: a JMP to the BDOS (0006H points here), the KFB layer, the HDOS file system, buffers |
| DA00H-E1FFH | HCCP, 2008 of 2048 bytes (variables and stack included) |
| E200H-EF7FH | BDOS, 3108 of the 3456 bytes that load, then its variables and 24-level stack |
| F000H-FFFFH | Heath BIOS |

Warm boot reloads D980H-EF7FH, so HCCP and the BDOS start fresh every
time. HCOS.SYS isn't reloaded. HCCP finds it by its signature and version,
resets it, hooks it into the BDOS again and points 0006H at it.

## What it does

All CP/M 2.2 functions 0–40:

- **Console:**
  - Line input with ^H, rubout, ^U, ^X, ^R, ^E and ^P, and ^C at the start
    of a line.
  - ^S stops output, and ^C during a stop reboots.
  - Tab expansion, column tracking, and direct I/O.
- **File system:**
  - Login builds the allocation vector and takes the directory checksums.
    A changed checksum makes the disk R/O.
  - Logical extents (EXM), modules (S2), and 8-bit or 16-bit block numbers.
  - Sequential and random I/O, including write with zero fill.
  - Error codes 1–6 as in 2.2.
  - User numbers, attributes, and the R/O and login vectors.
- **Errors:** "Bdos Err On d: Bad Sector / Select / R/O / File R/O", with
  DRI's error vectors at E209H for programs that patch them.

Things the CCP and loader depend on, found by running them:

- **Function 13 returns FFH** when logging in the drive finds a name
  starting with "$" in the current user area. The CCP takes that as "run
  $$$.SUB".
- **Close copies the FCB's extent and record count** into the directory
  unless the entry's extent is further on. The CCP shortens $$$.SUB by
  closing it with a smaller count.
- **A failed random seek leaves the FCB marked "not written"**, so the
  next close doesn't fail on an extent that was never opened.

## Testing

`tests/cpmdiff.sh` runs every test under Heath CP/M and under HCOS and
requires identical output:

- **Test programs** (`tests/cpm/*.asm`):
  - the console calls;
  - a file-system test covering make, writing across extents, reading to
    the end, file size, random I/O into module 1 and past the data, zero
    fill, rename, attributes, delete, search, user numbers, the vectors,
    the DPB and the allocation vector.
- **Sessions with CP/M's own programs** (`tests/cpm/*.steps`), compared by
  their final screens:
  - the CCP built-ins;
  - STAT, PIP, ED, DDT;
  - SUBMIT;
  - ED + ASM + LOAD building and running a program.

`make test-hcos` then runs the whole HDOS.COM suite again, booting HCOS.
That covers HDOS BASIC, PIP on CP/M and HDOS disks, and the differential
HDOS tests.

## Where this differs from the architecture draft

- **Drivers:** HCOS uses the Heath BIOS as its driver layer instead of its
  own H17 driver. The draft already puts drivers behind a CP/M-BIOS-shaped
  jump table, and the Heath BIOS is one. Writing a timing-critical
  hard-sector driver would have added risk without proving anything new.
  An own driver is still possible later, behind the same table.
- **Size:** the kernel has to fit the BDOS's space in the system tracks.
  So KAPI and KFB are not separate layers yet. The FCB is the file block
  (as the draft intended for CP/M disks), and there is one file system.

## HCCP (phase 4)

HCCP behaves like the CP/M 2.2 CCP:

- the same entry points (DA00H with a command, DA03H without) and command
  buffer, so the BIOS's auto-start works;
- built-ins DIR, ERA, REN, SAVE, TYPE and USER, with CP/M's messages;
- SUBMIT through $$$.SUB;
- programs loaded up to DA00H, with "BAD LOAD" past that;
- DRI's line handling and output.

The CP/M sessions in `tests/cpm/` give identical screens under HCCP and
DRI's CCP. Details found by reading what the DRI CCP does:

- CR LF before a program runs.
- A blank line after an error echo ("NAME?").
- 0004H holds user and drive while a line is typed and a program runs,
  and the drive alone otherwise.

On top of that:

- **CAT** is DIR.
- **`NAME`** with no NAME.COM runs NAME.ABS through A:HDOS.COM, with the
  command line as its arguments.
- At cold boot HCCP loads **HCOS.SYS**.

## HCOS.SYS and KFB (phase 4)

CP/M programs use HDOS disks through the BDOS:

- **The hook:** the BDOS has a hook vector at E211H (`KXVEC`). Before it
  selects the drive for an FCB call, it offers the call there. HCCP points
  it at HCOS.SYS's `kxhook` at every boot.
- **Which drives:** the call is handled there when the drive is an HDOS
  disk, detected as HDOS.COM does. Otherwise the BDOS carries on as usual.
- **The code:** HCOS.SYS is built from HDOS.COM's own file-system modules
  (`hdosfs`, `hdoswr`, `hdosdir`, `bios`), with a few small routines of its
  own (`kxlib.asm`) and the KFB layer (`kfb.asm`):
  - An open file gets a slot laid out like an HDOS.COM channel, so the
    modules work on it unchanged. The FCB's map holds "K" and the slot
    number; the record count and the rest keep their CP/M meaning.
  - Record r is half (r AND 1) of HDOS sector r/2, through a one-sector
    buffer. Writes read the sector, change the half and write it back,
    adding sectors past the end.
  - Make enters the file at once (CP/M's rule, not HDOS's), because
    programs such as PIP open what they have made.
  - Searches return one directory entry a file. HDOS's W and S flags
    become CP/M's R/O and SYS.
  - It runs on its own stack: the BDOS's is too small for its call depth.

Tests: on an HDOS disk, HCCP's DIR and CP/M PIP's copies in both
directions, with [V] verify; ERA and REN; and real HDOS listing the files
the CP/M programs wrote.

### Limits

- **STAT** on an HDOS disk reports CP/M allocation data, which is
  meaningless there.
- **Search with "?" in the drive byte** (every entry) still goes to the
  CP/M side.
- **HDOS text** is LF-only. CP/M's TYPE shows it stepped, because no
  conversion is done (open question Q1).
- **HDOS programs get less memory under HCOS:** HDOS.COM's buffers go below
  HCOS.SYS.
