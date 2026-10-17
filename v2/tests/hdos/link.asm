; link.asm - .LINK runs a program with the stack and A as they were,
; the ^A/^B/^C handlers cleared and the file open on channel -1. The
; test links to itself; a flag in high memory tells the runs apart.

	include	test.inc

FLAG	equ	8000h
BUF	equ	4000h

TESTMAIN:
	sta	FLAG+4			; A at entry
	lhld	FLAG
	mov	a,l
	cpi	'L'
	jnz	first
	mov	a,h
	cpi	'K'
	jz	second
first:	call	PSTR
	db	'{{',12Q,0
	lxi	h,nnope			; a missing program: error back
	lxi	d,defabs
	SCALL	.LINK
	push	psw
	call	PSTR
	db	'NOPE',0
	pop	psw
	call	PRES
	call	PNL
	mvi	a,1			; a ^A handler, to be cleared
	lxi	h,first
	SCALL	.CTLC
	lxi	h,'L'+256*'K'
	shld	FLAG
	lxi	h,1234h			; marker on the stack
	push	h
	lxi	h,0
	dad	sp
	shld	FLAG+2
	mvi	a,5
	lxi	h,nself
	lxi	d,defabs
	SCALL	.LINK
	call	PSTR
	db	'LINK FAILED',12Q,'}}',12Q,0
	xra	a
	SCALL	.EXIT

second:	lxi	h,0
	shld	FLAG
	call	PSTR
	db	'SECOND A=',0
	lda	FLAG+4
	call	PHEX
	lxi	h,0			; SP as it was?
	dad	sp
	xchg
	lhld	FLAG+2
	mov	a,l
	cmp	e
	jnz	sp.bad
	mov	a,h
	cmp	d
	jnz	sp.bad
	call	PSTR
	db	' SP OK',0
sp.bad:	pop	h
	call	PSTR
	db	' TOP=',0
	call	PHEXW
	call	PSTR
	db	' CCTAB=',0
	lhld	S.CCTAB
	call	PHEXW
	call	PNL
	mvi	a,-1			; channel -1: the program file
	lxi	b,0
	SCALL	.POSIT
	push	psw
	call	PSTR
	db	'CH-1 POSIT',0
	pop	psw
	call	PRES
	mvi	a,-1
	lxi	b,256
	lxi	d,BUF
	SCALL	.READ
	push	psw
	call	PSTR
	db	' READ',0
	pop	psw
	call	PRES
	lxi	h,BUF
	mvi	b,4
ch1:	mvi	a,' '
	SCALL	.SCOUT
	mov	a,m
	call	PHEX
	inx	h
	dcr	b
	jnz	ch1
	call	PNL
	call	PSTR
	db	'}}',12Q,0
	xra	a
	SCALL	.EXIT

defabs:	db	'SY0ABS'
nnope:	db	'NOPE',0
nself:	db	'LINK',0

TESTLEN	equ	$-USERFWA
