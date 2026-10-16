# The HCOS kernel

Phase 3 of HCOS: **an operating system that boots from disk and runs CP/M
2.2 programs on its own BDOS.** The BDOS is written from the CP/M 2.2
interface (`src/kernel/`) and contains no DRI code. It replaces the DRI
BDOS in the system tracks of a Heath CP/M disk, so it loads on every cold
and warm boot.

```sh
make hcos      # build/disks/hcos.h8d: the test CP/M disk, booting HCOS
python3 tools/sysgen.py YOUR.h8d build/kernel/bdos.cim OUT.h8d
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
| 0100H-D9FFH | TPA, the same 56K as Heath CP/M |
| DA00H-E1FFH | CCP (still DRI's; HCCP is phase 4) |
| E200H-EBFFH | HCOS BDOS: code and tables, 3075 of the 3456 bytes that load |
| EC00H-EF7FH | its variables and its 24-level stack (zeroed on load; function 13 resets them) |
| F000H-FFFFH | Heath BIOS |

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

## Next (phase 4)

The HDOS personality and file system move from HDOS.COM into the kernel.
They need more room than the BDOS has (381 bytes left). The plan:

- A smaller HCOS command processor (HCCP) in the CCP's 2K, which also runs
  `.ABS` programs.
- An extension loaded below DA00H at cold boot. HCCP lowers the TPA top in
  page zero to protect it.
