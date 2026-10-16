; kxload.asm - HCCP's part in the kernel extension (see kext.asm)

; kxinit - at cold boot load A:HCOS.SYS (user 0) to KXBASE; at every
; boot hook it into the BDOS and point the TPA top at it. Nothing if
; there's no HCOS.SYS. Uses all; changes user and DMA.
kxinit:	call	kxok			; in memory already?
	jz	kx.on
	mvi	e,0			; load it
	call	setusr
	lxi	h,kxname		; FCB at 005CH (free now)
	lxi	d,kxfcb
	mvi	b,12
	call	movb
	mvi	b,36-12
	xra	a
kx0:	stax	d
	inx	d
	dcr	b
	jnz	kx0
	lxi	d,kxfcb
	mvi	c,F_OPEN
	call	sys
	inr	a
	rz
	lxi	h,KXBASE
kx1:	push	h
	xchg
	mvi	c,F_DMAOFF
	call	sys
	lxi	d,kxfcb
	mvi	c,F_READ
	call	sys
	pop	h
	ora	a
	jnz	kx2
	lxi	d,128
	dad	d
	mov	a,h			; no further than KXEND
	cpi	KXEND shr 8
	jc	kx1
kx2:	call	kxok
	rnz
kx.on:	call	KX.RST			; it starts afresh
	mvi	a,0C3h			; the BDOS offers it FCB calls
	sta	KXVEC
	lxi	h,KX.HOOK
	shld	KXVEC+1
	lxi	h,KXBASE		; and programs stop below it
	shld	BDOS+1
	ret

; kxok - Z if the extension is in memory: signature and version.
kxok:	lxi	h,KXBASE+KXSIGO
	lxi	d,kxsig
	mvi	b,5
kxo1:	ldax	d
	cmp	m
	rnz
	inx	h
	inx	d
	dcr	b
	jnz	kxo1
	lda	KX.VER
	cpi	KXVER
	ret

kxsig:	db	'HCKX'
	db	0C3h			; (then the JMP kxhook)
kxname:	db	1,'HCOS    SYS'
kxfcb	equ	DFCB
