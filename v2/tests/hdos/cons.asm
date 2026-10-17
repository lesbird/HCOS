; cons.asm - console output, .VERS, .CONSL, system area cells, .SETTP
; and .LOADO.

	include	test.inc

TESTMAIN:
	call	PSTR
	db	'{{',12Q,0
	SCALL	.VERS			; version
	push	psw
	call	PSTR
	db	'VERS',0
	pop	psw
	call	PRES
	call	PNL

	mvi	a,3			; .CONSL read width (C = 0)
	mvi	c,0
	SCALL	.CONSL
	push	psw
	call	PSTR
	db	'WIDTH',0
	pop	psw
	call	PRES
	call	PNL

	mvi	a,5			; .CONSL bad index
	SCALL	.CONSL
	push	psw
	call	PSTR
	db	'CONSL5',0
	pop	psw
	call	PRES
	call	PNL

	call	PSTR			; tabs expand to columns 9, 17
	db	'A',11Q,'B',11Q,'C|',12Q,0
	call	PSTR			; .PRINT, cursor after it
	db	'CUR',0
	lxi	h,ptext
	SCALL	.PRINT
	lda	S.CUSOR
	call	PHEX
	call	PNL

	call	PSTR			; mode and type cells
	db	'CSLMD=',0
	lda	S.CSLMD
	call	PHEX
	call	PSTR
	db	' CONTY=',0
	lda	S.CONTY
	call	PHEX
	call	PSTR
	db	' CONFL=',0
	lda	S.CONFL
	call	PHEX
	call	PNL

	call	PSTR			; RST vector slots are JMPs
	db	'UIVEC',0
	lxi	h,.UIVEC
	mvi	b,7
uv:	mvi	a,' '
	SCALL	.SCOUT
	mov	a,m
	call	PHEX
	inx	h
	inx	h
	inx	h
	dcr	b
	jnz	uv
	call	PNL

	call	PSTR			; S.USRM = load + length
	db	'START',0
	call	PSTR
	db	' USRM=',0
	lhld	S.USRM
	call	PHEXW
	call	PNL

	lhld	S.SYSM			; .SETTP: too high, then OK
	inx	h
	SCALL	.SETTP
	push	psw
	xchg
	lhld	S.SYSM
	dcx	h
	dcx	h
	call	PSTR
	db	'SETTP HI',0
	pop	psw
	call	PRES
	mov	a,l			; HL came back as S.SYSM-2?
	cmp	e
	jnz	bad
	mov	a,h
	cmp	d
	jnz	bad
	call	PSTR
	db	' MAX OK',0
bad:	lxi	h,3000h
	SCALL	.SETTP
	call	PRES
	lhld	S.USRM
	call	PSTR
	db	' USRM=',0
	call	PHEXW
	call	PNL

	call	PSTR			; .LOADO: overlays 0 and 1, then a
	db	'LOADO',0		; bad one
	mvi	a,0
	SCALL	.LOADO
	call	PRES
	mvi	a,1
	SCALL	.LOADO
	call	PRES
	mvi	a,2
	SCALL	.LOADO
	call	PRES
	call	PNL

	call	PSTR
	db	'}}',12Q,0
	xra	a
	SCALL	.EXIT

ptext:	db	'xyz',' '+200Q

TESTLEN	equ	$-USERFWA
