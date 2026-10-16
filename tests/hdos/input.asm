; input.asm - .SCIN in line mode with editing, then character mode.
; Typed: a b BS c DEL d Return. BS is a rubout (CTP.BKM is set), so
; the line is "ad". Echo is off so only what the program gets is
; compared. A is not printed when .SCIN has nothing (it is junk).

; WAIT: READY>
; KEYS: ab\bc\177d\r

	include	test.inc

TESTMAIN:
	xra	a			; echo off
	mvi	b,CSL.ECH
	mvi	c,CSL.ECH
	SCALL	.CONSL
	call	PSTR
	db	'{{',12Q,0
	SCALL	.SCIN			; nothing typed yet
	call	pcy
	call	PSTR
	db	' typed',12Q,'READY>',0
	lxi	h,line
in1:	SCALL	.SCIN			; collect up to NL
	jc	in1
	mov	m,a
	inx	h
	cpi	12Q
	jnz	in1
	call	PSTR
	db	12Q,'LINE',0
	lxi	d,line
in2:	mvi	a,' '
	SCALL	.SCOUT
	ldax	d
	call	PHEX
	inx	d
	mov	a,e
	cmp	l
	jnz	in2
	call	PNL

	xra	a			; character mode, no echo
	mvi	b,CSL.CHR+CSL.ECH
	mvi	c,CSL.CHR+CSL.ECH
	SCALL	.CONSL
	push	psw
	push	psw
	call	PSTR
	db	'CONSL',0
	pop	psw
	call	PRES
	call	PSTR
	db	' MODE=',0
	pop	psw
	call	PHEX
	SCALL	.SCIN			; nothing waiting
	call	pcy
	call	PNL
	SCALL	.CLRCO
	call	PSTR
	db	'}}',12Q,0
	xra	a
	SCALL	.EXIT

; Print " C=x" for the carry.
pcy:	mvi	a,0
	aci	0
	push	psw
	call	PSTR
	db	' C=',0
	pop	psw
	adi	'0'
	SCALL	.SCOUT
	ret

line:	ds	32

TESTLEN	equ	$-USERFWA
