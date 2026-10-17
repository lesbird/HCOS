; kxload.asm - the shell's part in the HDOS extension (see src/hdosx/)

; kxinit - at every boot. If the extension is in memory, its KX.RST
; resets it, hooks it into the BDOS and points the TPA top at it. If
; not, and the BDOS has found an HDOS disk since (KXNEED), put the
; command A:HDOSFS in the buffer: HDOSFS.COM moves the extension to
; KXBASE and installs it. It stays until the next cold boot.
kxinit:	lxi	h,KXBASE+KXSIGO		; in memory already?
	lxi	d,kxsig
	mvi	b,5
kxo1:	ldax	d
	cmp	m
	jnz	kx1
	inx	h
	inx	d
	dcr	b
	jnz	kxo1
	lda	KX.VER
	cpi	KXVER
	jz	KX.RST
kx1:	lxi	h,KXNEED
	mov	a,m
	ora	a
	rz				; not needed
	mvi	m,0
	lxi	h,kxcmd
	lxi	d,cblen
	mvi	b,KXCLEN
	jmp	movb

kxsig:	db	'HCKX'
	db	0C3h			; (then the JMP kxhook)
kxcmd:	db	KXCLEN-1,'A:HDOSFS'
KXCLEN	equ	$-kxcmd
