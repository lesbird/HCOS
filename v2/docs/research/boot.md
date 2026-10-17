# Research: booting, the memory switch, console and clock (R1, R5)

Phase 0 findings for HCOS version 2. Sources:

- disassembly of MTR-90 (444-142) and the H17 ROM (444-19);
- the Heath CP/M disks `build/disks/cpm.h8d` (H17) and `cpm37.h37` (H37),
  and `hdos.h8d`;
- Heath's BIOS.SYS, both as stored on disk and as it sits in memory
  after booting;
- HDOS 3.0 source (mgarlanger/asmx `testHdos/source`: `mtr.acm`,
  `mtrram.acm`, `edvec.acm`, `edram.acm`, `hosequ.acm`, `hos3.h8a`);
- runs in the H89 emulator. A small harness linked against
  `libh89core.a` (breakpoints, register and memory dumps, I/O trace) and
  test boot records were used.

Addresses are hex. Anything not confirmed is marked [UNVERIFIED].

## 1. H17 boot (MTR-90 "B", SW501 = 20H)

### What MTR-90 does (0287H)

1. It selects the boot device from SW501 (`IN F2`, bit 4 = primary at
   170Q). The device table at 0F43H is used for 174Q and the one at 0F54H
   for 170Q. Each entry holds a type byte (to 2151H), the highest unit
   digit, and the routine. Types are taken from SW501 bits 0-1 (174Q) or
   bits 2-3 (170Q):
   - 174Q type 0 is the H17, routine 0287H;
   - 170Q type 0 is the H37, routine 0991H;
   - type 1 at either port goes to 01FAH (H47 [UNVERIFIED]).

   The port base goes to 2150H (7CH or 78H) and the unit to 2131H. "B"
   boots unit 0. "B1", "B2" and "BS" (secondary) also work.
2. It copies 58H bytes from 1F5AH to 2048H: D.CON (2048H-2057H) and the
   D.VEC jump table (2058H-209FH).
3. It points D.SDP's target (2086H) at 0224H. This is MTR-90's own
   select-drive routine:
   - it sets 10 retries (20B4H);
   - it takes the unit from 2131H;
   - it maps unit 2 to DS2 (port 7FH bit 3) correctly;
   - it then joins R.SDP at 1E3BH.
4. It points the clock hook at 2020H to 04C4H for the length of the boot.
   This hook watches for DEL on the console (which aborts the boot), then
   calls 1C19H.
5. It waits for 10 index holes. Through 0F14H it seeks to track 0, then
   track 10, then track 0 again.
6. `CALL 1C3FH` (R.READ) with DE=2280H, BC=0900H, HL=0. This reads
   **sectors 0-8 of track 0 (2304 bytes) into 2280H-2B7FH**. On error it
   prints "?Boot Error" (0279H).
7. At 0E8DH:
   - DI, then 2020H := 1C19H (the H17 ROM clock routine), then EI;
   - 2156H-215AH are cleared;
   - **JP 2280H**.

The H17 ROM's own boot at 1F0CH (for PAM-8 machines) does the same: it
reads 0900H bytes to 2280H and jumps there.

### Machine state at the jump to 2280H

All of this was measured at the breakpoint.

| Item | State |
|---|---|
| Memory | ROM in. GPP = 82H: no ORG-0, clock on, bit 7 set by the monitor (meaning [UNVERIFIED]). 0000H-0FFFH is MTR-90, 1400H-17FFH is the H17 RAM, 1800H-1FFFH is the H17 ROM, 2000H and up is RAM |
| Interrupts | EI, IM 0. The 2 ms clock is running through the ROM's RST 1 |
| SP | 2280H, so the stack grows down into 2200H-227FH |
| Registers | AF=0042H, BC=0000H, DE=00BCH, HL=215BH. Not meaningful |
| 2008H .MFLAG | 01H (UO.CLK: the ROM calls 201FH each tick; bit 7 clear, so the ROM's HALT check is on) |
| 2009H .CTLFLG | D0H |
| 201BH .TICCNT | 16-bit tick count |
| 201DH .REGPTR | the interrupted SP, saved by the ROM |
| 201FH-2033H .UIVEC | 201FH JP 1C19H (clock). The others are JP 1C17H (EI; RET) |
| 2034H .NMIRET | 008DH |
| 2036H .CTL2FL | 80H |
| 2048H-209FH | D.CON and D.VEC, as copied from the ROM. 2085H D.SDP is JP 0224H |
| 20A0H-20BEH D.RAM | live. After the read: D.TT=0, D.TS=8, D.DVCTL=10H (motor on), D.DLYMO=78H, D.DLYHS=01H, D.TRKPT=20A9H, D.VOLPT=20AAH |
| 2131H | boot unit (0) |
| 2132H-214EH | boot string typed after "B n:" [UNVERIFIED use] |
| 2150H | boot device port, 7CH |
| 2151H | device type byte from the table (00H) |
| 2152H | boot timeout counter (01H) |
| Port 7FH | 10H: motor on, no drive selected |

### Heath CP/M's boot record: the "1E00H to D980H" answer

v1's note is **right about the effect but not about who does it**. MTR-90
loads only 0900H bytes. The CP/M boot record at 2280H loads the rest by
calling the ROM itself. The code (bytes at disk offset 001DH):

```
229D  LXI B,1E00H ; LXI D,0D980H ; LXI H,0 ; CALL 1C3FH (R.READ)
22A9  JC 22B0H    ; DI ; JMP 0F000H
22B0  DI ; RST 0
```

That is sectors 0-29, which is all 3 system tracks (7.5K), loaded to
D980H-F77FH. The boot record lands at D980H, the CCP at DA00H, the BDOS
at E200H and a loader BIOS at F000H. The jump to the loader BIOS at F000H
has the ROM still in and interrupts off. In the emulator the 30-sector
read took 1.02 s, and F000H was reached 2.2 s after reset.

The loader BIOS (at F0EEH) then:

1. DI.
2. Reads (0000H): it is C3H on the H89 and something else on an H8.
3. `OUT F2,22H`: ORG-0 and the clock. 22H is kept in 000DH.
4. On an H8 only, `OUT F0,D0H`. The H8 value is kept in 000EH.
5. Copies 2150H (boot port) to 0049H and 2131H (boot unit) to 0004H, and
   puts 40H in 0048H.
6. Fills the RST slots with EI; RET, and puts JP F362H at 0008H.
7. EI.

It then loads BIOS.SYS through the BDOS with its own small H17 driver.

The HDOS 2.0 boot record works the same way. It too copies D.CON and
D.VEC from 1F5AH and puts its own copy of MTR-90's select-drive routine
at 2086H (22B5H). It then reads HDOS through the ROM routines.

## 2. Calling the H17 ROM's disk read from a boot record: yes

Heath's CP/M boot record already does it (above). It was also proved
with a test boot record: `rtest.asm` written over sector 0 of a copy of
`cpm.h8d`, with `hdos.h8d` in SY1:. Every read compared equal to the
image:

| Call | Result |
|---|---|
| HL=395, BC=0180H, DE=3000H | a partial sector. The rest of the sector is read and dropped, and 3180H and up is untouched |
| HL=205, BC=0A00H, DE=3200H | 10 sectors, crossing from track 20 to 21 (the ROM seeks by itself) |
| (2131H):=1, HL=0, BC=0900H | read from SY1: |
| HL=399, BC=0100H | the last sector of the disk |

Each call returned A=0, NC, Z.

### R.READ (1C3FH, also through D.READ at 2067H)

| | |
|---|---|
| Entry | HL = sector number 0-399 (track = HL/10, sector = HL mod 10). DE = buffer. BC = byte count (a partial last sector is allowed). The unit comes from D.SDP, that is from 2131H through 0224H or 1E32H |
| Exit | NC and A=0 if it worked. C and A = error code if not (12H read failure, after D.OECNT retries). BC, DE and HL are destroyed |
| Side effects | Interrupts are left enabled: R.SDP, R.XOK and the seek code do EI themselves, so a DI before the call doesn't hold. Motor left on, drive deselected. Error counters in D.RAM |
| Volume | The header's volume byte must equal the drive's entry in D.DRVTB (20AAH+2×unit). It is 0 after boot. CP/M disks (and track 0 of any disk) have volume 0. For HDOS tracks 1-39, set the volume first (R.MOUNT 1BE5H with L = volume [UNVERIFIED usage]). R.READR (1CD1H) reads with volume 0 |
| Bad sector numbers | No range check. HL=400 (track 40) was still retrying after 120 s, so don't do it |

Other entries, from the vector table at 1F6AH (in RAM at 2058H):

| Entry | Address |
|---|---|
| R.SYDD | 1BCEH |
| R.MOUNT | 1BE5H |
| R.XOK | 1BFCH |
| D.ABORT | 1BF6H (asmx's `hdsrom.acm` gives 1BDEH, which is wrong for this ROM) |
| R.XIT | 1BFDH |
| R.READ | 1C3FH |
| R.READR | 1CD1H |
| R.WRITE | 1CDEH |
| R.SDP | 1E32H |
| R.DLY | 1DC3H |
| CLOCK | 1C19H |

### What R.READ needs

- **RAM:**
  - D.CON, D.VEC and D.RAM (2048H-20BEH), set up as above;
  - .TICCNT (201BH);
  - 2131H (unit), read by R.SDP or 0224H;
  - the caller's stack.

  The R.* disk code makes **no use of the H17 RAM at 1400H** and calls
  nothing in the monitor ROM.
- **The 2 ms clock with the ROM's RST 1 handler.** R.DLY (step and settle
  delays) spins on .TICCNT, which only the ROM's RST 1 handler counts.
  Test: `OUT F2,80H` (clock off) before the call hung in R.DLY at 1DC8H.
- **201FH → JP 1C19H with .MFLAG bit 0 set.** 1C19H runs every 4 ms. It
  counts down D.DLYHS (head settle and motor start, in 4 ms units) and,
  every 512 ms, D.DLYMO (motor off). Test: 2020H pointed at a RET and
  D.DLYMO zeroed (as if the motor were off) hung in R.LPS/R.STS at 1EC2H.
  It still works with the hook dead while the motor is already running,
  because no delay is then armed. Don't rely on that.
- **Speed:** 9 sectors in 0.24 s; 30 sectors over 3 tracks in 1.02 s.

So a boot record running with the ROM in can read anything on an H17
disk with R.READ, as long as it doesn't disturb 2000H-20BEH, 201FH or
2131H, and leaves interrupts on.

HDOS 3.0 (GO0 in `hos3.h8a`) does something else worth knowing. It
copies the H17 ROM (1800H-1FFFH) into RAM *under* ORG-0, so the R.*
routines still run with RAM at 0000H, given a RAM clock handler that
counts 201BH and calls 1C19H.

## 3. H37 boot (MTR-90, SW501 = 30H)

### What MTR-90 does (0991H)

1. Resets the controller:
   - `OUT 79,0`;
   - `OUT 7A,D0H` (force interrupt);
   - waits 2 ms with `.DLY` (002BH);
   - reads the status.
2. Points the RST 4 vector at the INTRQ handler: **2028H := JP 0A65H**.
   The handler does `IN 7A` (status into A), drops the interrupted PC,
   then `EI` and `JMP (2037H)`, so each command's continuation is kept
   in 2037H.
3. Sets the control port: `OUT 78`, (DS(unit) | 0DH) = 1DH for unit 0.
   That is INTRQ enable, bit 2 (MFM in the emulator), motor and DS0.
   It then does EI and waits 96H ticks (300 ms).
4. Restore (03H), seek to track 10 (13H), restore again, and checks
   TRACK0. Each command spins until INTRQ jumps to its continuation. The
   restore has a software timeout.
5. Read (0A3DH):
   - control |= 02H (DRQ enable);
   - sector register := 1;
   - DE := 2280H;
   - `OUT 7A,9CH`: Read Sector, multiple-record, so it reads to the end
     of the track;
   - a `HALT; IN 7B; STAX D; INX D` loop, in which the card answers each
     DRQ with EI, ending the HALT;
   - the record-not-found at the end of the track raises INTRQ, which
     ends the loop at 0A5CH. There, `OUT 78,08H` (motor only, deselect,
     interrupts off) and the status is ANDed with ACH (RNF ignored).
6. It first tries with bit 2 set (1FH) and then, if that fails, with it
   clear (1BH). It accepts the result if it read 0900H bytes or more.
   For `cpm37.h37` (single density, 10 × 256) the first try read nothing
   and the second read 2280H-2C7FH: **all 10 sectors of track 0, side 0,
   2560 bytes**.
7. It joins the H17 exit at 0E81H:
   - copies D.CON and D.VEC (D.SDP is the ROM's 1E32H this time);
   - 2020H := 1C19H;
   - **JP 2280H**.

### State at 2280H

The same as for the H17 boot, except:

| Item | State |
|---|---|
| 2150H | 78H |
| 2028H | JP 0A65H |
| 2037H | 0A5CH |
| Port 78H | 08H (motor on, no drive selected) |
| D.RAM | cleared, not used |

Timing: 2280H was reached at 3.2 s, most of it the failed first try.

### Is there a reusable 1797 read routine in MTR-90? Not really

0A3DH has sector 1 and DE=2280H fixed and reads to the end of the track.
Entering at 0A52H with your own DE, HL=0A56H and (2037H)=0A5CH would
work, but it is an undocumented internal entry point
[UNVERIFIED across ROM revisions].

Heath's H37 boot record carries **its own** 1797 code (2280H-2366H, about
230 bytes with density and step options). It reuses only MTR-90's RST 4
vector (2028H → 0A65H, continuation in 2037H) and the HALT/DRQ
mechanism. It reads 3BH sectors to D100H, then does `OUT 78,08`, DI and
JP E800H, to the H37 loader BIOS. (Heath's H17/H37 BIOS sits at
E800H-FFFFH.)

## 4. The memory switch: port F2H (362Q)

Write: OP2.CTL. Bit names from HDOS 3.0's `mtrram.acm`:

| Bit | Name | Meaning |
|---|---|---|
| 0 | CB2.SSI | single-step interrupt (RST 2). The emulator ignores it (TODO) |
| 1 | CB2.CLI | 2 ms clock interrupt enable (RST 1) |
| 5 | CB2.ORG | ORG-0: RAM at 0000H-1FFFH, so the ROMs and the H17 RAM at 1400H disappear. The emulator honours it only with 64K RAM |
| 6 | CB2.SID | side 1 select [UNVERIFIED, not emulated] |
| 7 | (none) | set by MTR-90 (82H) [UNVERIFIED meaning] |

Read: SW501 (IP.CON):

| Bits | Name | Meaning |
|---|---|---|
| 0-1 | CN.174M | device type at 174Q (00 = H17) |
| 2-3 | CN.170M | device type at 170Q (00 = H37) |
| 4 | CN.PRI | 1 = the primary boot device is at 170Q |
| 5 | CN.MEM | 0 = memory test |
| 6 | CN.BAU | 1 = 19200 baud |
| 7 | CN.ABO | auto-boot |

Who writes it:

- **MTR-90:**
  - at reset, `OUT F2,02H`;
  - on every clock tick, the ROM's RST 1 handler does
    `OUT F0,(.CTLFLG)`. On the H89, an access to ports F0H, F1H, FAH or
    FBH raises an **NMI**. The NMI handler (0066H → 044EH) emulates the
    H8 front panel: F2 := (CB.CLI → bit 1) | (CB.SSI → bit 7, and bit 0
    when SSI is clear) | .CTL2FL. It then stores the result, ANDed with
    FCH, in .CTL2FL. An IN from F0H gives FFH, and an IN from FAH or FBH
    gives 00H. So with the ROM in, GPP is rewritten from 2009H and 2036H
    every 2 ms.
- **Heath CP/M BIOS:** 22H (ORG-0 and the clock), kept in page-zero cell
  000DH and written again on every clock tick.
- **HDOS 3.0:** `.CTL2FL = CB2.ORG+CB2.CLI` (22H), written again on every
  tick.
- **v1 HCOS:** 22H in C-mode, 02H in H-mode.

Everyone rewrites OP2.CTL on every tick. It is probably needed on real
hardware (to clear or re-arm the clock latch [UNVERIFIED]). The emulator
clears the clock request on the interrupt acknowledge, and clearing bit 1
drops a pending one.

**Switching:** while the ROM is in, writes to 0000H-13FFH go nowhere (the
emulator drops them). Page zero therefore can't be prepared beforehand.
The order is: DI; `OUT F2,22H`; write 0008H (and 0018H, 0038H, 0066H if
used); EI. Heath's loader does exactly this. With RAM in, an access to
F0H, F1H, FAH or FBH NMIs into RAM 0066H. Heath's BIOS has nothing at
0066H and simply never touches those ports on an H89.

## 5. Console and clock (R5)

### 8250 at E8H as MTR-90 leaves it

At reset (0400H):

1. LCR=80H.
2. Divisor 000CH (9600 baud), or 0006H (19200) if SW501 bit 6 is set
   (from the table at 0441H).
3. LCR=03H: 8 bits, no parity, 1 stop.
4. IER=00H: polled, no interrupts.

MCR isn't written, so it is 00H after reset. RST 3 (0018H → JP 2025H)
is just EI; RET.

### Heath CP/M's console

The BIOS in memory, H17 version at F000H:

- **Cold boot:**
  - for each port (console E8H, D0H, E0H, D8H), from the table at
    F037H, which CONFIGUR changes: LCR=83H, MCR=0FH, the divisor
    (console 000CH, 9600, **fixed: SW501 bit 6 is not read**), LCR=03H,
    IER=00H;
  - RST 3 at 0018H := JP F9A8H.
- **CONIN** is **interrupt driven**:
  - CONST (F961H) writes IER=01H (receive interrupt) each time and
    reports whether the 40-byte ring buffer (FEBAH-FEE1H) has anything;
  - the RST 3 handler (F9A8H) reads IIR and the data, puts the byte in
    the ring, and sends BEL when it is over 36 full;
  - CONIN waits on the count and takes a byte under DI.
- **CONOUT** polls LSR bit 5 (THRE), then writes the data register.
- **Ports FAH/FBH (372Q/373Q)** are the H8-5's 8251 USART (FAH data,
  FBH status/command):
  - it is used only when bit 0 of the BIOS byte at F036H is set;
  - cold boot sets that bit on an H8 (000EH ≠ 0) when no 8250 answers at
    the console base;
  - it initialises the 8251 with 15H, 40H (reset), 4EH (8 bits, ×16,
    1 stop) and 17H.

  On an H89 these ports are never touched.
- **Ports 00H/01H** are not real ports. They are the placeholder port
  bytes of self-modifying IN and OUT instructions. The BIOS fills them
  in at run time from the port table (base + register), for example
  0984H `OUT 00H` becomes `OUT E9H`, and 0B9EH `IN 00H` becomes
  `IN EDH`. The same is true in the H37 BIOS.

### Clock

**ROM in.** RST 1 (0008H runs into 0009H) is the ROM's handler. It:

1. saves all registers;
2. increments .TICCNT;
3. does `OUT F0` (the NMI rewrites GPP);
4. with .CTLFLG bit 5 clear, does a HALT check unless .MFLAG bit 7 is
   set. If the interrupted code was a HALT, it drops to the monitor with
   a beep. **So a boot record must not HALT with the ROM in**, except
   the H37 DRQ HALT: DRQ enable masks the other interrupts;
5. if .MFLAG bit 0 is set, calls 201FH;
6. restores the registers, EI; RET.

`.DLY` at 002BH waits A ticks on .TICCNT.

**RAM in (Heath BIOS, F821H, at 0008H).** It:

1. saves HL and AF only;
2. `OUT F2,(000DH)`;
3. on an H8, `OUT F0,(000EH)`;
4. increments the tick count at 000BH (16 bits);
5. every 256 ticks, counts down the motor-off timer (F81EH) and the
   deselect timer (F81FH), clearing bits in the 7FH image at 000FH;
6. every 2nd tick, counts down a delay cell (F820H);
7. EI; RET.

A BIOS taking the clock needs:

1. JP handler at 0008H, installed under DI after ORG-0 is on;
2. GPP bit 1 on in the value written to F2H, rewritten every tick;
3. a handler that saves what it uses and ends with EI; RET.

## 6. Implications for the HCOS v2 boot record and BIOS

1. **Boot record size:** MTR-90 gives an H17 boot record 2304 bytes
   (sectors 0-8, at 2280H) and an H37 boot record 2560 bytes (track 0,
   at 2280H). It starts at 2280H with SP=2280H, EI, the ROM in and
   GPP=82H.
2. **H17:** the boot record can load the system tracks and HCOS.SYS's
   sectors with `R.READ` (1C3FH: HL=sector, DE=buffer, BC=bytes; C on
   error), exactly as Heath's CP/M boot record does. It needs no driver.
   It must:
   - leave 2000H-20BEH, 201FH, 2131H and the ROM clock alone;
   - keep interrupts on;
   - not HALT;
   - keep its stack and buffers away from 2000H-227FH.

   HCOS disks have volume 0 everywhere, so no R.MOUNT is needed. Reading
   is about 1 s per 3 tracks, plus seeks, and MTR-90 itself takes about
   1.2 s before the boot record runs.
3. **H37:** the boot record needs its own small 1797 read, about 60-100
   bytes, as Heath's has. It can reuse MTR-90's INTRQ vector (2028H →
   0A65H, continuation in 2037H) and the HALT/DRQ loop, or install its
   own at 2028H. It must handle the density (MTR-90 tries bit 2 set,
   then clear) and the sector numbering from 1.
4. **The switch into the BIOS:**
   1. DI;
   2. `OUT F2,22H`;
   3. write page zero: 0008H clock, 0018H (if console interrupts are
      used), 0038H, and 0066H (NMI: RETN, to be safe against stray
      F0H/F1H/FAH/FBH accesses);
   4. EI.

   Keep the GPP value in a cell and write it again on every tick, as
   Heath's BIOS (000DH) and HDOS 3.0 (.CTL2FL) do.
5. **The ROM after the switch:** once RAM is in, nothing of the ROM is
   usable. That fits the plan's own H17 driver in the BIOS. A fallback
   is HDOS 3.0's trick: copy 1800H-1FFFH into RAM under ORG-0, plus a
   clock that counts 201BH and calls 1C19H. It is also the way to run
   R7's INIT, SYSGEN and TEST17 later.
6. **Console:** start from MTR-90's settings, but set the divisor from
   SW501 bit 6 (Heath's BIOS ignores it) and MCR=0FH. Polled output on
   LSR bit 5. Input can be polled (LSR bit 0) for size, or interrupt
   driven with a ring buffer as in Heath's BIOS (type-ahead), with
   IER=01H and a handler at 0018H. Leave out H8-5 (FAH/FBH) support
   until the H8 phase.
7. **HDOS programs in H-mode (later)** need .MFLAG, .CTLFLG and .CTL2FL
   set as HDOS sets them, and 2020H set to a valid clock hook, because
   the ROM's NMI handler rebuilds GPP from them every tick.
