; bios.asm - the HCOS v2 BIOS
;
; The CP/M 2.2 jump table at BIOSB, then HCOS's own entries. The cold
; boot and memory switch, the console (8250) and the 2 ms clock. The console has a 32-byte type-ahead buffer, filled
; by the 8250's receive interrupt (RST 3), so keys typed while a
; program is busy aren't lost. Three H17 drives (h17.asm). Warm boot
; reloads the shell and the BDOS from the reserved tracks only if a
; program has changed them.
;
; The boot record jumps to BOOT with interrupts off and the ROM still
; in. Written from the CP/M 2.2 interface and the phase 0 research
; (docs/research/boot.md, h17.md); no Heath or DRI code.

	.8080
	include	layout.inc

	org	BIOSB

	jmp	boot
	jmp	wboot
	jmp	const
	jmp	conin
	jmp	conout
	jmp	list
	jmp	punch
	jmp	reader
	jmp	home
	jmp	seldsk
	jmp	settrk
	jmp	setsec
	jmp	setdma
	jmp	read
	jmp	write
	jmp	listst
	jmp	sectran
	jmp	ticks
	assert	$ == B.TICKS+3

; ---- Cold and warm boot ----

boot:	lxi	sp,stack
	lhld	TICCNT		; the ROM has counted since reset
	shld	tickc
	mvi	a,GP.ORG+GP.CLI	; RAM in at 0000H, clock on
	sta	gppv
	out	GPP
	call	page0
	call	coninit
	call	dinit
	lxi	h,SYSTAB	; the sums, before a program can touch them
	lxi	d,wbtab
	mvi	b,8
	call	cpyn
	ei
	lxi	h,signon
	call	print
	mvi	a,0a9h		; IOBYTE, as Heath's (the BIOS ignores it)
	sta	0003h
	xra	a
	sta	0004h		; drive A:, user 0
	jmp	gocpm

; Warm boot: reload the shell and the BDOS if their code has changed.
wboot:	lxi	sp,stack
	di
	call	page0
	ei
	lda	hstwrt		; a sector still to be written
	ora	a
	cnz	writehst
	xra	a
	sta	hstact
	lxi	h,wbtab	; the shell: sectors 1-8
	mvi	b,1
	call	chksys
	lxi	h,wbtab+4	; the BDOS: sectors 9-22
	mvi	b,9
	call	chksys
gocpm:	mvi	a,0c3h		; 0005H: JMP to the BDOS
	sta	0005h
	lxi	h,BDOSB+6
	shld	0006h
	lda	0004h
	mov	c,a
	jmp	SHELLB+3

; HL -> the length and sum of a part that starts at sector B. Reload
; it from drive A if its sum isn't right any more.
chksys:	mov	e,m		; DE = length
	inx	h
	mov	d,m
	inx	h
	push	h
	mov	h,b		; HL = its address, D900H + 256 * B
	mvi	l,0
	lxi	b,SYSB
	dad	b
	push	h
	lxi	b,0		; BC = the sum
cks1:	mov	a,d
	ora	e
	jz	cks2
	mov	a,m
	add	c
	mov	c,a
	jnc	cks1a
	inr	b
cks1a:	inx	h
	dcx	d
	jmp	cks1
cks2:	pop	d		; DE = address
	pop	h
	mov	a,m		; the same?
	cmp	c
	jnz	reload
	inx	h
	mov	a,m
	cmp	b
	rz
; Read sectors from the one at DE up to the next part (the shell: 1-8,
; the BDOS: 9-22) from drive A, in physical order.
reload:	xra	a
	sta	hstdsk
	mov	a,d		; sector = (DE - D900H) / 256
	sui	SYSB shr 8
	sta	rlsec
rl1:	mvi	b,0		; track = sector / 10
rl2:	sui	10
	jc	rl3
	inr	b
	jmp	rl2
rl3:	adi	10
	sta	physec
	mov	a,b
	sta	hsttrk
	call	h17rdp
	jc	rlerr
	lda	rlsec		; to its place
	adi	SYSB shr 8
	mov	d,a
	mvi	e,0
	lxi	h,hstbuf
	mvi	b,0
rl4:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	rl4
	lxi	h,rlsec
	inr	m
	mov	a,m
	cpi	9		; the shell ends at sector 8
	rz
	cpi	(BIOSB-SYSB) shr 8 ; the BDOS at the BIOS
	rz
	jmp	rl1
rlerr:	lxi	h,wbmsg
	call	print
	call	conin
	jmp	wboot

; Page zero: JMP WBOOT at 0000H, the clock at 0008H, the console at
; 0018H, EI; RET in the other RST slots, and RETN at 0066H in case anything touches ports
; F0H, F1H, FAH or FBH (an NMI on the H89). Called with interrupts off.
; 0003H-0007H (IOBYTE, drive, BDOS jump) are left as they are.
page0:	lxi	h,0
	mvi	m,0c3h
	inx	h
	lxi	d,B.WBOOT
	mov	m,e
	inx	h
	mov	m,d
	mvi	l,08h		; RST 1: the clock
	mvi	m,0c3h
	inx	h
	lxi	d,clock
	mov	m,e
	inx	h
	mov	m,d
	mvi	l,10h		; RST 2-7: EI; RET
p0rst:	mvi	m,0fbh
	inx	h
	mvi	m,0c9h
	mov	a,l
	adi	7
	mov	l,a
	cpi	40h
	jc	p0rst
	mvi	l,18h		; RST 3: the console
	mvi	m,0c3h
	inx	h
	lxi	d,conint
	mov	m,e
	inx	h
	mov	m,d
	mvi	l,66h		; NMI
	mvi	m,0edh		; RETN (Z80; the 8080 has no NMI)
	inx	h
	mvi	m,45h
	ret

; Disks: nothing selected, every track unknown, buffer empty. The motor
; is left running, as the ROM's boot leaves it, so the first access
; doesn't wait for it to start again; the timer stops it later.
dinit:	mvi	a,DF.MO
	sta	s7f
	out	DP.CTL
	mvi	a,T.OFF
	sta	mtim
	xra	a
	sta	hstact
	sta	hstwrt
	sta	unacnt
	dcr	a
	lxi	h,h17trk
	mov	m,a
	inx	h
	mov	m,a
	inx	h
	mov	m,a
	ret

; ---- Clock: RST 1, every 2 ms ----
; Writes the general purpose port again on every tick, as Heath's BIOS
; and HDOS 3.0 do, and counts.

clock:	push	psw
	lda	gppv
	out	GPP
	push	h
	lhld	tickc
	inx	h
	shld	tickc
	mov	a,l		; every 512 ms: the motor-off timer
	ora	a
	jnz	clk9
	lxi	h,mtim
	ora	m
	jz	clk9		; stopped
	dcr	m
	jnz	clk9
	lda	s7f		; time: motor off, no drive selected
	ani	0e1h
	sta	s7f
	out	DP.CTL
clk9:	pop	h
	pop	psw
	ei
	ret

ticks:	lhld	tickc
	ret

; ---- Console: the 8250 at 350Q ----
; Input comes in by interrupt into a 32-byte ring at rbuf. Only the
; interrupt moves rin and only CONIN moves rout, so neither needs DI.
; A key that arrives with the ring full is dropped. Output is polled.

coninit:
	mvi	a,83h		; divisor latch
	out	CON.LCR
	in	GPP		; SW501 bit 6: 19200 baud, else 9600
	ani	SW.BAU
	mvi	a,12		; 1.8432 MHz / 16 / 9600
	jz	ci1
	mvi	a,6
ci1:	out	CON
	xra	a
	out	CON+1
	mvi	a,03h		; 8 bits, no parity, 1 stop
	out	CON.LCR
	mvi	a,0fh		; DTR, RTS, OUT1, OUT2
	out	CON.MCR
	mvi	a,rbuf and 0ffh
	sta	rin
	sta	rout
	in	CON		; drop anything already there
	mvi	a,01h		; interrupt on received data
	out	CON.IER
	ret

; RST 3: a key.
conint:	push	psw
	push	h
	in	CON.LSR
	ani	01h
	jz	cint9
	lda	rin
	mov	l,a
	mvi	h,rbuf shr 8
	in	CON
	mov	m,a
	mov	a,l		; advance, unless that fills the ring
	inr	a
	ani	1fh
	ori	rbuf and 0ffh
	lxi	h,rout
	cmp	m
	jz	cint9
	sta	rin
cint9:	pop	h
	pop	psw
	ei
	ret

const:	lda	rout
	lxi	h,rin
	sub	m
	rz
	mvi	a,0ffh
	ret

conin:	call	const
	ora	a
	jz	conin
	lda	rout
	mov	l,a
	mvi	h,rbuf shr 8
	mov	b,m
	inr	a
	ani	1fh
	ori	rbuf and 0ffh
	sta	rout
	mov	a,b
	ani	7fh
	ret

conout:	in	CON.LSR
	ani	20h
	jz	conout
	mov	a,c
	out	CON
	ret

; Print HL until a 0.
print:	mov	a,m
	ora	a
	rz
	mov	c,a
	call	conout
	inx	h
	jmp	print

; ---- Other character devices: none ----

list:
punch:	ret

listst:	mvi	a,0ffh		; ready, so nothing waits on it
	ret

reader:	mvi	a,1ah		; end of file
	ret

; ---- Disks: three H17 drives ----
; CP/M's 128-byte records are packed two to a 256-byte host sector by
; DRI's blocking/deblocking algorithm (CP/M 2.2 Alteration Guide),
; written for HCOS. The skew between host sectors is applied by the
; driver, so the DPH has no XLT and SECTRAN changes nothing: the disks
; are laid out exactly as Heath's.

NDRIVE	equ	3
SPT	equ	20		; records a track
HSTSPT	equ	10		; host sectors a track
BLKREC	equ	8		; records a block (1K)
WRDIR	equ	1		; write type: directory, write it now
WRUAL	equ	2		; write type: first record of a new block

seldsk:	lxi	h,0
	mov	a,c
	cpi	NDRIVE
	rnc			; no such drive
	mov	a,e		; the first select since a reset: is the
	rar			; drive ready? (A select error if not, as
	jc	seld1		; on Heath CP/M)
	push	b
	mov	a,c
	call	h17rdy
	pop	b
	lxi	h,0
	rc
seld1:	mov	a,c
	sta	sekdsk
	mov	l,a		; HL = dph + 16 * drive
	dad	h
	dad	h
	dad	h
	dad	h
	lxi	d,dph
	dad	d
	ret

home:	lda	hstwrt		; keep a sector that is waiting to be written
	ora	a
	jnz	home1
	sta	hstact
home1:	lxi	b,0
settrk:	mov	a,c
	sta	sektrk
	ret

setsec:	mov	a,c
	sta	seksec
	ret

setdma:	mov	l,c
	mov	h,b
	shld	dma
	ret

sectran: mov	l,c
	mov	h,b
	ret

read:	xra	a
	sta	unacnt
	inr	a
	sta	readop
	sta	rsflag		; read the host sector first
	mvi	a,WRUAL
	sta	wrtype
	jmp	rwoper

write:	xra	a
	sta	readop
	mov	a,c
	sta	wrtype
	cpi	WRUAL
	jnz	chkuna
	mvi	a,BLKREC	; a new block: its records need no pre-read
	sta	unacnt
	lxi	h,sekdsk
	lxi	d,unadsk
	call	cpy3
chkuna:	lxi	h,unacnt
	mov	a,m
	ora	a
	jz	alloc
	dcr	m		; still in the new block?
	lxi	h,sekdsk
	lxi	d,unadsk
	call	cmp3
	jnz	alloc
	lxi	h,unasec	; yes: the next record of it
	inr	m
	mov	a,m
	cpi	SPT
	jc	noovf
	mvi	m,0
	lxi	h,unatrk
	inr	m
noovf:	xra	a
	sta	rsflag
	jmp	rwoper
alloc:	xra	a
	sta	unacnt
	inr	a
	sta	rsflag

; Find the record's host sector, in the buffer or from the disk, then
; move the record. sekdsk/sektrk/seksec, readop, rsflag and wrtype say
; what to do. A = 0, or 1 on an error.
rwoper:	xra	a
	sta	erflag
	lda	seksec
	ora	a
	rar			; host sector = record / 2
	sta	sekhst
	lxi	h,hstact
	mov	a,m
	mvi	m,1
	ora	a
	jz	filhst		; the buffer was empty
	lxi	h,sekdsk	; the same host sector?
	lxi	d,hstdsk
	mvi	b,2
	call	cmpn
	jnz	rw1
	lda	sekhst
	lxi	h,hstsec
	cmp	m
	jz	match
rw1:	lda	hstwrt		; another: write the buffer out first
	ora	a
	cnz	writehst
filhst:	lxi	h,sekdsk
	lxi	d,hstdsk
	mvi	b,2
	call	cpyn
	lda	sekhst
	sta	hstsec
	lda	rsflag
	ora	a
	cnz	readhst
	xra	a
	sta	hstwrt
match:	lda	seksec		; the record's half of hstbuf
	rar
	mvi	a,0
	rar			; 80H for the second half
	mov	e,a
	mvi	d,0
	lxi	h,hstbuf
	dad	d
	xchg			; DE = in hstbuf
	lhld	dma
	mvi	b,128
	lda	readop
	ora	a
	jnz	mv2		; a read: from hstbuf to dma
	mvi	a,1		; a write: from dma, and the buffer is changed
	sta	hstwrt
	xchg
mv2:	ldax	d		; from DE to HL
	mov	m,a
	inx	d
	inx	h
	dcr	b
	jnz	mv2
	lda	wrtype
	cpi	WRDIR
	lda	erflag
	rnz
	ora	a
	rnz			; an error already
	sta	hstwrt		; directory: write it now
	call	writehst
	lda	erflag
	ret

writehst:
	call	h17wr
	jmp	hsterr
readhst:
	call	h17rd
hsterr:	rnc
	mvi	a,1
	sta	erflag
	xra	a		; the buffer is no good now
	sta	hstact
	ret

; Compare or copy 3 bytes (drive, track, sector) at HL and DE, or B.
cmp3:	mvi	b,3
cmpn:	ldax	d
	cmp	m
	rnz
	inx	d
	inx	h
	dcr	b
	jnz	cmpn
	ret
cpy3:	mvi	b,3
cpyn:	mov	a,m
	stax	d
	inx	d
	inx	h
	dcr	b
	jnz	cpyn
	ret

	include	h17.asm

; DPHs: no XLT, scratch, DIRBUF, DPB, CSV, ALV.
dph:	dw	0,0,0,0,dirbuf,dpb,csv0,alv0
	dw	0,0,0,0,dirbuf,dpb,csv0+CKS,alv0+ALVLEN
	dw	0,0,0,0,dirbuf,dpb,csv0+2*CKS,alv0+2*ALVLEN

; The Heath H17 format: single-sided, 40 tracks, 1K blocks, 3 reserved
; tracks (docs/research/h17.md, 4.4).
DSM	equ	91
CKS	equ	16
ALVLEN	equ	DSM/8+1
dpb:	dw	SPT
	db	3,7,0		; BSH, BLM, EXM
	dw	DSM,63		; DSM, DRM
	db	0c0h,0		; AL0, AL1
	dw	CKS,3		; CKS, OFF

signon:	db	0dh,0ah,'HCOS 2.0',0dh,0ah,0
wbmsg:	db	0dh,0ah,'Warm boot error, press a key',0dh,0ah,0

	assert	$ <= SYSEND

; ---- Variables, not on disk ----

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
; the H17 driver
s7f	equ	erflag+1	; what is in port 7FH (not the step bits)
mtim	equ	s7f+1		; motor off, in 512 ms, 0 = stopped
h17w	equ	mtim+1		; 1 = writing
retry	equ	h17w+1
physec	equ	retry+1
tdl	equ	physec+1	; tick deadline
h17trk	equ	tdl+2		; each drive's track, FFH = unknown
wbtab	equ	h17trk+NDRIVE	; SYSTAB, kept from the cold boot
rlsec	equ	wbtab+8	; warm boot: the sector being reloaded
rbuf	equ	(rlsec+1+1fh) and 0ffe0h ; 32 bytes, 32-aligned
hstbuf	equ	rbuf+32		; 256
dirbuf	equ	hstbuf+256	; 128
alv0	equ	dirbuf+128
csv0	equ	alv0+NDRIVE*ALVLEN
stack	equ	csv0+NDRIVE*CKS+64
	assert	stack <= 10000h
