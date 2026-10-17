; ctlc.asm - a ^C handler set with .CTLC runs at the next SCALL, with
; A = 1 and a return address that resumes the program.
; KEYS: \003

	include	test.inc

TESTMAIN:
	mvi	a,3
	lxi	h,onctlc
	SCALL	.CTLC
	push	psw
	call	PSTR
	db	'CTLC',0
	pop	psw
	call	PRES
	mvi	a,4			; only 1-3 are valid
	lxi	h,onctlc
	SCALL	.CTLC
	call	PRES
	call	PNL
	call	PSTR
	db	'{{',12Q,0
wait:	SCALL	.SCIN			; until the handler has run
	lda	hit
	ora	a
	jz	wait
	call	PSTR
	db	'RESUMED',12Q,'}}',12Q,0
	xra	a
	SCALL	.EXIT

onctlc:	sta	hita
	mvi	a,1
	sta	hit
	call	PSTR
	db	'HANDLER A=',0
	lda	hita
	call	PHEX
	call	PNL
	ret

hit:	db	0
hita:	db	0

TESTLEN	equ	$-USERFWA
