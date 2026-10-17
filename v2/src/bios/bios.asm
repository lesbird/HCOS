; bios.asm - the HCOS v2 BIOS (phase 1: no disks yet)
;
; The CP/M 2.2 jump table at BIOSB, then HCOS's own entries. Phase 1
; has the cold boot and memory switch, the console (8250, polled) and
; the 2 ms clock. The console has a 32-byte type-ahead buffer, filled
; by the 8250's receive interrupt (RST 3), so keys typed while a
; program is busy aren't lost. The disk entries are stubs that fail, and warm boot
; re-enters the shell without reloading it.
;
; The boot record jumps to BOOT with interrupts off and the ROM still
; in. Written from the CP/M 2.2 interface and the phase 0 research
; (docs/research/boot.md); no Heath or DRI code.

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
	ei
	lxi	h,signon
	call	print
	xra	a
	sta	0004h		; drive A:, user 0
	mov	c,a
	jmp	SHELLB

wboot:	lxi	sp,stack
	di
	call	page0
	ei
	lda	0004h
	mov	c,a
	jmp	SHELLB+3

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
	pop	h
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

; ---- Disks: phase 2 ----

seldsk:	lxi	h,0		; no such drive
	ret

home:	lxi	b,0
settrk:	mov	l,c
	mov	h,b
	shld	track
	ret

setsec:	mov	a,c
	sta	sector
	ret

setdma:	mov	l,c
	mov	h,b
	shld	dma
	ret

read:
write:	mvi	a,1		; error
	ret

sectran: mov	l,c
	mov	h,b
	ret

signon:	db	0dh,0ah,'HCOS 2.0',0dh,0ah,0

	assert	$ <= SYSEND

; ---- Variables, not on disk ----

gppv	equ	BIOSRAM		; the value kept in the general purpose port
tickc	equ	gppv+1		; 2 ms ticks since reset
track	equ	tickc+2
sector	equ	track+2
dma	equ	sector+1
rin	equ	dma+2	; ring: next free slot (low byte)
rout	equ	rin+1		; ring: next key (low byte)
rbuf	equ	(rout+1+1fh) and 0ffe0h ; 32 bytes, 32-aligned
stack	equ	rbuf+32+64
