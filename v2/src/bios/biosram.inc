; biosram.inc - the BIOS's variables and buffers, from BIOSRAM up (not on
; disk), and the second driver's slot (H17/H37 build). bios.asm and a
; driver assembled for the slot both include it.

	include	layout.inc

; Drives: A:-C: on the boot controller (the BIOS's own driver); in the
; H17/H37 build D:-F: on the other one, through the slot.
	if	BIOSB < 0F000h
SLOTS	equ	1
NDRIVE	equ	6
	else
SLOTS	equ	0
NDRIVE	equ	3
	endif
; BIOS entries for a driver in the slot (H17/H37 build): the clock's
; deadlines (see h17.asm: tdead, tpast, twait).
B.TDEAD	equ	BIOSB+63
B.TPAST	equ	BIOSB+66
B.TWAIT	equ	BIOSB+69

DSM	equ	91		; every format so far: SS SD, 92 1K blocks
CKS	equ	16
ALVLEN	equ	DSM/8+1

gppv	equ	BIOSRAM		; the value kept in the general purpose port
tickc	equ	gppv+1		; 2 ms ticks since reset
rin	equ	tickc+2		; ring: next free slot (low byte)
rout	equ	rin+1		; ring: next key (low byte)
dma	equ	rout+1
; deblocking: sekdsk-seksec, hstdsk-hstsec and unadsk-unasec are each
; drive, track, sector in that order
sekdsk	equ	dma+2
sektrk	equ	sekdsk+1
seksec	equ	sektrk+1
sekhst	equ	seksec+1
hstdsk	equ	sekhst+1
hsttrk	equ	hstdsk+1
hstsec	equ	hsttrk+1
unadsk	equ	hstsec+1
unatrk	equ	unadsk+1
unasec	equ	unatrk+1
unacnt	equ	unasec+1
hstact	equ	unacnt+1
hstwrt	equ	hstact+1
readop	equ	hstwrt+1
rsflag	equ	readop+1
wrtype	equ	rsflag+1
erflag	equ	wrtype+1
hunit	equ	erflag+1	; the drive's unit on its controller
; the H17 driver
s7f	equ	hunit+1	; what is in port 7FH (not the step bits)
mtim	equ	s7f+1		; motor off, in 512 ms, 0 = stopped
h17w	equ	mtim+1		; 1 = writing
retry	equ	h17w+1
physec	equ	retry+1
phwr	equ	physec+1	; B.PHYS: 1 = write
tdl	equ	phwr+1		; tick deadline
h17trk	equ	tdl+2		; each unit's track, FFH = unknown
; the H37 driver (h37.asm)
latch	equ	h17trk+3	; what is in the control latch
mtim37	equ	latch+1		; motor off, in 512 ms, 0 = stopped
dkrtry	equ	mtim37+1
dkcmd	equ	dkrtry+1
dksec	equ	dkcmd+1
dktrk	equ	dksec+1		; each unit's track, FFH = unknown
h37act	equ	dktrk+3		; a command is waiting for INTRQ
h37st	equ	h37act+1	; status at INTRQ
h37cmp	equ	h37st+1		; where INTRQ goes then
wbtab	equ	h37cmp+2	; SYSTAB, kept from the cold boot
rlsec	equ	wbtab+8	; warm boot: the sector being reloaded
rlcnt	equ	rlsec+1		; reloads since the cold boot
rbuf	equ	(rlcnt+1+1fh) and 0ffe0h ; 32 bytes, 32-aligned
hstbuf	equ	rbuf+32		; 256
dirbuf	equ	hstbuf+256	; 128
alv0	equ	dirbuf+128
csv0	equ	alv0+NDRIVE*ALVLEN
dphram	equ	csv0+NDRIVE*CKS	; DPHs, 16 bytes a drive (SELDSK)
stack	equ	dphram+NDRIVE*16+64

; The slot (H17/H37 build): a driver loaded at cold boot (H37.COM)
; copies itself here. It starts with this entry table; until it is
; loaded, the BIOS's cold boot fills it with "not ready" stubs.
;   SL.RD   read host sector hstsec of hsttrk, unit hunit, to hstbuf
;   SL.WR   write it from hstbuf
;   SL.RDY  A = unit: NC if it is ready
;   SL.PHY  A = 0: read physical sector physec (0-9), 1: write it
;           (B.PHYS)
;   SL.TICK every 512 ms, from the clock interrupt (motor timer)
;   SL.ISR  RST 4 (H37 INTRQ), from 0020H
;   SL.INIT once, when it has been copied here
; RD, WR, RDY and PHY return CY and A = an error code on failure.
SLOTB	equ	(stack+0FFh) and 0FF00h
SL.RD	equ	SLOTB
SL.WR	equ	SLOTB+3
SL.RDY	equ	SLOTB+6
SL.PHY	equ	SLOTB+9
SL.TICK	equ	SLOTB+12
SL.ISR	equ	SLOTB+15
SL.INIT	equ	SLOTB+18
SLOTN	equ	7		; entries
	if	SLOTS
	assert	SLOTB+800h <= 10000h	; 2K for the driver and its RAM
	else
	assert	stack <= 10000h
	endif

