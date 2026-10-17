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
	include	biosram.inc

	org	BIOSCB

; ---- Cold boot ----
; It runs once, so it lives in the last page below the BIOS, which the
; BDOS doesn't use (layout.inc), and the BIOS proper keeps its room.

boot:	lxi	sp,stack
	lhld	TICCNT		; the ROM has counted since reset
	shld	tickc
	mvi	a,GP.ORG+GP.CLI	; RAM in at 0000H, clock on
	sta	gppv
	out	GPP
	if	SLOTS
	call	slinit
	endif
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
	if	SLOTS
	in	GPP		; SW501: the other controller there? (H37
	if	CORE37		; at 170Q, H17 at 174Q.) Then the shell
	ani	03h		; runs A:H17 or A:H37 first, which loads
	else			; its driver into the slot.
	ani	0ch
	endif
	jnz	gocpm
	lxi	h,h37cmd
	lxi	d,SHELLB+7	; the shell's command buffer
	mvi	b,H37CL
	call	cpyn
	call	setbd
	mvi	c,0
	jmp	SHELLB
	endif
	jmp	gocpm

; Disks: the buffer empty, and the driver's own start.
dinit:	xra	a
	sta	hstact
	sta	hstwrt
	sta	unacnt
	sta	rlcnt
	jmp	cini

; Console: 9600 baud (19200 with SW501 bit 6), 8N1, and the type-ahead.
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

	if	SLOTS
; The slot's entries until a driver is there: not ready, and nothing
; for the clock or RST 4.
slinit:	lxi	h,SLOTB
	lxi	d,slnull
	mvi	b,SLOTN
sli1:	mvi	m,0c3h
	inx	h
	ldax	d
	mov	m,a
	inx	h
	inx	d
	ldax	d
	mov	m,a
	inx	h
	inx	d
	dcr	b
	jnz	sli1
	ret
slnull:	dw	slnr,slnr,slnr,slnr,slret,sleir,slret
slnr:	mvi	a,80h
	stc
slret:	ret
sleir:	ei
	ret
	if	CORE37
h37cmd:	db	H37CL-2,'A:H17',0
	else
h37cmd:	db	H37CL-2,'A:H37',0
	endif
H37CL	equ	$-h37cmd
	endif
	assert	$ <= BIOSB
	ds	BIOSB-$

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
	jmp	conint
	jmp	tickr
	jmp	phys
	assert	$ == B.PHYS+3
	if	SLOTS
	jmp	tdead
	jmp	tpast
	jmp	twait
	assert	$ == B.TWAIT+3
	endif

; ---- Warm boot ----
; Reload the shell and the BDOS if their code has changed.
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
	lxi	b,SHSUMB
	call	chksys
	lxi	h,wbtab+4	; the BDOS: sectors 9-22
	lxi	b,BDSUMB
	call	chksys
gocpm:	call	setbd
	lda	0004h
	mov	c,a
	jmp	SHELLB+3

; 0005H: JMP to the BDOS.
setbd:	mvi	a,0c3h
	sta	0005h
	lxi	h,BDOSB+6
	shld	0006h
	ret

; HL -> the length and sum of the code from BC. Reload the part it is
; in from drive A if the sum isn't right any more.
chksys:	mov	e,m		; DE = length
	inx	h
	mov	d,m
	inx	h
	push	h
	mov	h,b
	mov	l,c
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
reload:	lxi	h,rlcnt		; (counted, for the tests)
	inr	m
	xra	a
	sta	hunit
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
	xra	a		; read physec
	call	cop
	jc	rlerr
	lda	rlsec		; to its place
	adi	SYSB shr 8
	mov	d,a
	mvi	e,0
	lxi	h,hstbuf
	call	cp256
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
	if	SLOTS
	mvi	l,20h		; RST 4: the H37's INTRQ, to its driver
	mvi	m,0c3h
	inx	h
	if	CORE37
	lxi	d,dkisr
	else
	lxi	d,SL.ISR
	endif
	mov	m,e
	inx	h
	mov	m,d
	endif
	mvi	l,66h		; NMI
	mvi	m,0edh		; RETN (Z80; the 8080 has no NMI)
	inx	h
	mvi	m,45h
	ret

; ---- Clock: RST 1, every 2 ms ----
; Writes the general purpose port again on every tick, as Heath's BIOS
; and HDOS 3.0 do, and counts.

clock:	push	psw
	lda	gppv
	out	GPP
	push	h
	jmp	clk1
; The ROM's clock handler calls this (through 201FH) with the ROM in.
; The ROM looks after the general purpose port then.
tickr:	push	psw
	push	h
clk1:	lhld	tickc
	inx	h
	shld	tickc
	mov	a,l		; every 512 ms: the motor-off timer
	ora	a
	jnz	clk9
	call	ctck		; (the driver's)
	if	SLOTS
	call	SL.TICK		; (and the slot's)
	endif
clk9:	pop	h
	pop	psw
	ei
	ret

ticks:	lhld	tickc
	ret

; Tick deadlines. tdead: the deadline is HL ticks from now. tpast: CY
; while it hasn't come. Interrupts must be on.
tdead:	xchg
	lhld	tickc
	dad	d
	shld	tdl
	ret
tpast:	lhld	tdl
	xchg
	lhld	tickc
	mov	a,l
	sub	e
	mov	a,h
	sbb	d
	ral			; CY = the sign: now < deadline
	ret

; Wait HL ticks.
twait:	call	tdead
tw1:	call	tpast
	jc	tw1
	ret


; ---- Console: the 8250 at 350Q (coninit is with the cold boot) ----
; Input comes in by interrupt into a 32-byte ring at rbuf. Only the
; interrupt moves rin and only CONIN moves rout, so neither needs DI.
; A key that arrives with the ring full is dropped. Output is polled.

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
	call	drvrdy
	pop	b
	lxi	h,0
	rc
; The drive's DPH, in RAM: filled in here, so the reserved tracks don't
; carry a table. XLT 0, DIRBUF, the DPB, CSV and ALV.
seld1:	mov	a,c
	sta	sekdsk
	add	a
	add	a
	mov	c,a		; C = 4 * drive
	add	a
	add	a
	mov	b,a		; B = 16 * drive
	sub	c
	mov	c,a		; C = 12 * drive
	mov	e,b
	mvi	d,0
	lxi	h,dphram
	dad	d
	push	h
	xra	a
	mov	m,a
	inx	h
	mov	m,a
	lxi	d,7		; (then 6 bytes of BDOS scratch)
	dad	d
	lxi	d,dirbuf
	call	stde
	lxi	d,dpb
	call	stde
	push	h
	lxi	h,csv0		; 16 bytes a drive (CKS)
	mov	e,b
	mvi	d,0
	dad	d
	xchg
	pop	h
	call	stde
	push	h
	lxi	h,alv0		; 12 bytes a drive (ALVLEN)
	mov	e,c
	mvi	d,0
	dad	d
	xchg
	pop	h
	call	stde
	pop	h
	ret
	assert	CKS == 16
	assert	ALVLEN == 12

stde:	mov	m,e
	inx	h
	mov	m,d
	inx	h
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

	if	SLOTS
; Drives 0-2 are the BIOS's own driver's, 3-5 the slot's. hunit := the
; unit; CY for our own.
dvunit:	lda	hstdsk
	sui	3
	jnc	dvu1
	adi	3
	sta	hunit
	stc
	ret
dvu1:	sta	hunit
	ret
writehst:
	call	dvunit
	jnc	wh1
	call	cwr
	jmp	hsterr
wh1:	call	SL.WR
	jmp	hsterr
readhst:
	call	dvunit
	jnc	rh1
	call	crd
	jmp	hsterr
rh1:	call	SL.RD
	jmp	hsterr
; drvrdy - is drive A ready?
drvrdy:	sui	3
	jnc	SL.RDY
	adi	3
	jmp	crdy

	else
writehst:
	lda	hstdsk
	sta	hunit
	call	cwr
	jmp	hsterr
readhst:
	lda	hstdsk
	sta	hunit
	call	crd
	jmp	hsterr
drvrdy	equ	crdy
	endif
hsterr:	rnc
	mvi	a,1
	sta	erflag
	xra	a		; the buffer is no good now
	sta	hstact
	ret

; B.PHYS - a physical sector, for the HDOS file system (layout.inc).
phys:	push	h
	push	b
	push	d
	sta	phwr
	lda	hstwrt		; the host buffer is needed: write it out
	ora	a
	cnz	writehst
	xra	a
	sta	hstact
	pop	d
	mov	a,e
	sta	physec
	pop	b
	mov	a,b
	sta	hsttrk
	mov	a,c
	sta	hstdsk
	cpi	NDRIVE
	pop	h
	jnc	pherr
	push	h
	lxi	d,hstbuf
	lda	phwr
	ora	a
	cnz	cp256		; a write: from the caller's buffer
	if	SLOTS
	call	dvunit
	jnc	ph2
	endif
	lda	hstdsk
	sta	hunit
	lda	phwr		; read or write physec
	call	cop
	if	SLOTS
	jmp	ph3
ph2:	lda	phwr
	call	SL.PHY
ph3:
	endif
	pop	d
	jc	pherr
	lda	phwr
	ora	a
	lxi	h,hstbuf	; a read: to the caller's buffer
	cz	cp256
	xra	a
	ret
pherr:	mvi	a,1
	stc
	ret

; Copy 256 bytes from HL to DE.
cp256:	mvi	b,0
cp1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	cp1
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

; The BIOS's own driver: the boot controller's.
	if	CORE37
	include	h37.asm
crd	equ	dkrd
cwr	equ	dkwr
cop	equ	dkop
crdy	equ	dkrdy
ctck	equ	dktck
cini	equ	dkini
	else
	include	h17.asm
crd	equ	h17rd
cwr	equ	h17wr
cop	equ	h17op
crdy	equ	h17rdy
ctck	equ	h17tck
cini	equ	h17ini
	endif


; The Heath H17 format: single-sided, 40 tracks, 1K blocks, 3 reserved
; tracks (docs/research/h17.md, 4.4).
dpb:	dw	SPT
	db	3,7,0		; BSH, BLM, EXM
	dw	DSM,63		; DSM, DRM
	db	0c0h,0		; AL0, AL1
	dw	CKS,3		; CKS, OFF

signon:	db	0dh,0ah,'HCOS 2.0',0dh,0ah,0
wbmsg:	db	0dh,0ah,'BOOT ERROR',0

	assert	$ <= SYSEND
