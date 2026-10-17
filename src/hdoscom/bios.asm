; bios.asm - raw H17 sector reads and writes through the CP/M BIOS
;
; The Heath CP/M BIOS reads any H17 disk a sector at a time when it is
; called directly: BIOS track = physical track, BIOS sectors 1-20 are
; the two 128-byte halves of physical sectors 0-9 (no translation when
; READ is called directly). So HDOS sector n is track n/10, BIOS
; sectors 2*(n mod 10)+1 and +2. Checked against a real HDOS disk.
;
; After using the BIOS, the drive BDOS has selected is selected again,
; since BDOS doesn't expect the BIOS selection to change under it.

B.SELDSK equ	27		; BIOS jump table offsets
B.SETTRK equ	30
B.SETSEC equ	33
B.SETDMA equ	36
B.READ	equ	39
B.WRITE	equ	42

; rdsec - read HDOS sector HL of drive A (0 = A:) into the 256 bytes
; at DE. CY and A = EC.RF on error. Uses all.
; wrsec - write the 256 bytes at DE to it. CY and A = EC.WF on error.
rdsec:	push	psw
	xra	a
	jmp	rs0
wrsec:	push	psw
	mvi	a,1
rs0:	sta	rswr
	pop	psw
	sta	rsdrv
	xchg
	shld	rsdma
	xchg
	push	h			; track = n / 10, sector = n mod 10
	pop	b
	lxi	d,10
	call	rdu66			; HL = track, DE = sector
	shld	rstrk
	mov	a,e
	add	a
	inr	a
	sta	rssec			; first BIOS sector
	lda	rsdrv			; select the drive: E = 0 only the
	mov	c,a			; first time, as the BDOS does (the
	call	rsbit			; H37 BIOS logs a drive in again on
	mov	a,m			; every E = 0)
	ora	b
	cmp	m			; (Z: selected before)
	mov	m,a
	mvi	e,0
	jnz	rs1
	inr	e
rs1:	mvi	a,B.SELDSK
	call	bcall
	mov	a,h
	ora	l
	jz	rs.err			; no such drive
	lhld	rstrk
	mov	b,h
	mov	c,l
	mvi	a,B.SETTRK
	call	bcall
	call	rshalf			; both halves
	jc	rs.err
	lhld	rsdma
	lxi	d,128
	dad	d
	shld	rsdma
	lxi	h,rssec
	inr	m
	call	rshalf
	jc	rs.err
	call	bdsel
	xra	a
	ret
rs.err:	call	bdsel
	lda	rswr
	ora	a
	mvi	a,EC.RF
	stc
	rz
	mvi	a,EC.WF
	stc
	ret

; rshalf - read BIOS sector rssec into rsdma. CY on error.
rshalf:	lda	rssec
	mov	c,a
	mvi	b,0
	mvi	a,B.SETSEC
	call	bcall
	lhld	rsdma
	mov	b,h
	mov	c,l
	mvi	a,B.SETDMA
	call	bcall
	lda	rswr
	ora	a
	mvi	a,B.READ
	jz	rsh1
	lda	rssec			; write: the second half as a
	cma				; "directory" write (type 1), so
	ani	1			; the BIOS writes the sector now
	mov	c,a
	mvi	a,B.WRITE
rsh1:	call	bcall
	ora	a
	rz
	stc
	ret

; bdsel - select BDOS's current drive in the BIOS again. (Not in the
; kernel extension: it is called from inside the BDOS, which selects
; the drive again itself.)
bdsel:
	if	KX
	ret
	endif
	mvi	c,DRV_GET
	call	BDOS
	mov	c,a
	mvi	e,1			; already logged in
	mvi	a,B.SELDSK
	jmp	bcall

; bcall - call BIOS entry A (offset in the jump table).
bcall:	push	h
	lhld	BOOT+1			; WBOOT entry, base + 3
	dcx	h
	dcx	h
	dcx	h
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	xthl
	ret

rsdrv:	db	0
rsdma:	dw	0
rstrk:	dw	0
rssec:	db	0
rswr:	db	0			; 0 read, 1 write
rsseen:	db	0			; drives selected already (bit n)
