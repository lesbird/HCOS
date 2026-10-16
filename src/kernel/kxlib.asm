; kxlib.asm - small routines the HDOS file system modules use, for the
; kernel extension (in HDOS.COM they come from the H17 ROM library and
; from HDOS.COM's own modules)

; rdadap - HL = HL + A. Uses A, F.
rdadap:	add	l
	mov	l,a
	rnc
	inr	h
	ret

; rcomp - compare C bytes at DE and HL: Z if equal.
rcomp:	ldax	d
	cmp	m
	rnz
	inx	d
	inx	h
	dcr	c
	jnz	rcomp
	ret

; rmu86 - HL = A * DE. Uses A, F.
rmu86:	lxi	h,0
	push	d
mu1:	ora	a
	jz	mu3
	rar
	jnc	mu2
	dad	d
mu2:	xchg
	dad	h
	xchg
	jmp	mu1
mu3:	pop	d
	ret

; rdu66 - HL = BC / DE, DE = remainder (small values: by subtraction).
rdu66:	lxi	h,0
du1:	mov	a,c
	sub	e
	mov	a,b
	sbb	d
	jc	du2
	mov	a,c
	sub	e
	mov	c,a
	mov	a,b
	sbb	d
	mov	b,a
	inx	h
	jmp	du1
du2:	mov	d,b
	mov	e,c
	ret

; move - copy B bytes from HL to DE.
move:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	move
	ret

; cmphd - compare HL with DE: CY if HL < DE, Z if equal.
cmphd:	mov	a,h
	cmp	d
	rnz
	mov	a,l
	cmp	e
	ret

; zfill - zero BC bytes at HL.
zfill:	mvi	m,0
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	zfill
	ret

; setmode - set the current channel's mode to A.
setmode: lhld	chp
	mov	m,a
	ret

; (hrename's full form decodes an HDOS name; the extension uses hren2)
decode:	mvi	a,EC.IFN
	stc
	ret
zdef	equ	0
