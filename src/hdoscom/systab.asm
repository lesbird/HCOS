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


; sctrace - print " fff" (octal) for the SCALL being made.
sctrace: push	b
	push	d
	mvi	e,' '
	mvi	c,C_WRITE
	call	BDOS
	lda	scfn
	call	phexo
	pop	d
	pop	b
	ret

; .CRC16 (HDOS 3.0) - CRC-16 of BC bytes at HL starting from DE. Exit
; HL past them, DE = the CRC, BC = 0. (HDOS 3.0's algorithm.)
scrc16:	xchg
crc1:	ldax	d
	push	b
	mvi	b,8
crc2:	rlc
	mov	c,a
	dad	h
	mov	a,h
	ral
	xra	c
	rrc
	jnc	crc3
	mvi	a,80h
	xra	h
	mov	h,a
	mvi	a,05h
	xra	l
	mov	l,a
crc3:	mov	a,c
	dcr	b
	jnz	crc2
	pop	b
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	crc1
	xchg
	ret

; rsbit - drive C: HL -> rsseen, B = its bit. Keeps C.
rsbit:	lxi	h,rsseen
	mvi	b,1
	mov	a,c
rsb1:	ora	a
	rz
	push	psw
	mov	a,b
	add	a
	mov	b,a
	pop	psw
	dcr	a
	jmp	rsb1

