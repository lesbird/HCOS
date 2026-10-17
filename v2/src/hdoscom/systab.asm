; systab.asm - the SCALL trace, .CRC16, rsbit and sjump (the system
; tables are in hisys.asm)

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

; sjump - S.JUMPS n, with RAM in (from sjhi in hisys.asm).
sjump:	lxi	sp,hcstk		; "no S.JUMPS n" (0 S.SDD, 1 S.FASER,
	push	psw			; 2 S.DIREA, 3 S.FCI, 4 S.SCI)
	lxi	d,msjump
	mvi	c,C_WRITESTR
	call	BDOS
	pop	psw
	call	phexo
	jmp	hexit
msjump:	db	0dh,0ah,'HDOS.COM: no S.JUMPS $'
