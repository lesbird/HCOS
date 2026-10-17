; rommode.asm - H-mode: the monitor ROM is at 0000H. Reads the ROM's
; first bytes, calls the monitor's .DLY, types through the H17 ROM's
; $TYPTX, and makes SCALLs (console and a file) in ROM mode.
; HDOSFLAGS: /R

	include	test.inc

DLY	equ	002Bh			; monitor .DLY
TYPTX	equ	195Eh			; H17 ROM $TYPTX
BUF	equ	4000h

TESTMAIN:
	call	PSTR
	db	'{{',12Q,'ROM',0
	lxi	h,0
	mvi	b,4
r1:	mvi	a,' '
	SCALL	.SCOUT
	mov	a,m
	call	PHEX
	inx	h
	dcr	b
	jnz	r1
	lhld	.TICCNT			; .DLY 20: how many ticks?
	shld	t0
	mvi	a,20
	call	DLY
	lhld	t0
	xchg
	lhld	.TICCNT
	mov	a,l
	sub	e
	sta	dt
	call	PSTR			; (20, or 21 across a tick)
	db	' DLY ',0
	lda	dt
	cpi	20
	jc	dly1
	cpi	22
	jnc	dly1
	call	PSTR
	db	'OK',0
	jmp	dly2
dly1:	call	PHEX
dly2:
	call	PNL
	call	TYPTX
	db	'TYPTX OK',212Q
	mvi	a,0			; a file, from ROM mode
	lxi	h,nf
	lxi	d,defb
	SCALL	.OPENW
	call	PRES
	lxi	h,0100h			; the ROM, copied to RAM (SCALL
	lxi	d,BUF+100h		; buffers are in RAM, so programs
	mvi	b,0			; copy ROM data first)
cp1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	cp1
	mvi	a,0
	lxi	b,256
	lxi	d,BUF+100h
	SCALL	.WRITE
	call	PRES
	mvi	a,0
	SCALL	.CLOSE
	call	PRES
	mvi	a,0
	lxi	h,nf
	lxi	d,defb
	SCALL	.OPENR
	mvi	a,0
	lxi	b,256
	lxi	d,BUF
	SCALL	.READ
	call	PRES
	lda	BUF
	call	PHEX
	lda	BUF+1
	call	PHEX
	mvi	a,0
	SCALL	.CLOSE
	lxi	h,nf
	lxi	d,defb
	SCALL	.DELET
	call	PRES
	call	PNL
	call	PSTR
	db	'}}',12Q,0
	xra	a
	SCALL	.EXIT

t0:	dw	0
dt:	db	0
nf:	db	'ROMTEST.DAT',0
defb:	db	'SY0DAT'

TESTLEN	equ	$-USERFWA
