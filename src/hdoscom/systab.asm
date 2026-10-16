; systab.asm - S.GUP, the small system tables and the SCALL trace
; (kept apart only to place them after the ROM library)

; S.GUP - HL -> a unit table pointer (DEV.UNT), A = unit: HL -> that
; unit's entry. Uses F, H, L.
gup:	push	psw
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	pop	psw
	push	psw
	ani	7
	rlc
	rlc
	rlc
	call	rdadap
	pop	psw
	ret

chrunt:	db	DT.CHR,0
	dw	0,0,0

; Overlay table: both HDOS overlays in memory and resident, as they
; are in effect (PIP reads OVL.FLB).
ovltab:	dw	0,0,0
	db	3,0
	dw	0,0,0
	db	3,0

; A program called a device driver directly: not supported.
ddrv.x:	mvi	a,EC.DDA
	stc
	ret


; sctrace - print "[fff A=ooo]" (octal) for the SCALL being made.
sctrace: push	b
	push	d
	mvi	e,'['
	mvi	c,C_WRITE
	call	BDOS
	lda	scfn
	call	phexo
	lxi	d,mtra
	mvi	c,C_WRITESTR
	call	BDOS
	lda	sca
	call	phexo
	mvi	e,']'
	mvi	c,C_WRITE
	call	BDOS
	pop	d
	pop	b
	ret
mtra:	db	' A=$'

; phexo - print A as 3 octal digits through BDOS (for diagnostics).
phexo:	push	psw
	rlc
	rlc
	ani	3
	call	phexo1
	pop	psw
	push	psw
	rrc
	rrc
	rrc
	ani	7
	call	phexo1
	pop	psw
	ani	7
phexo1:	adi	'0'
	mov	e,a
	mvi	c,C_WRITE
	jmp	BDOS

