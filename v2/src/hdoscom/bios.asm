; bios.asm - raw H17 sector reads and writes through the CP/M BIOS
;
; The HCOS v2 BIOS takes records 0-19 of a track and skews its host
; sectors: records 2L and 2L+1 are the two halves of physical sector
; skew(L). So HDOS sector n is track n/10, records 2*L and 2*L+1 with
; L = invskew(n mod 10). (Version 1, on the Heath BIOS, used records
; 1-20 unskewed.)
;
; After using the BIOS, the drive BDOS has selected is selected again,
; since BDOS doesn't expect the BIOS selection to change under it.

BO.SELDSK equ	27		; BIOS jump table offsets
BO.SETTRK equ	30
BO.SETSEC equ	33
BO.SETDMA equ	36
BO.READ	equ	39
BO.WRITE	equ	42

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
	lxi	h,invskw
	dad	d
	mov	a,m
	add	a
	sta	rssec			; first BIOS record
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
rs1:	mvi	a,BO.SELDSK
	call	bcall
	mov	a,h
	ora	l
	jz	rs.err			; no such drive
	lhld	rstrk
	mov	b,h
	mov	c,l
	mvi	a,BO.SETTRK
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
	mvi	a,BO.SETSEC
	call	bcall
	lhld	rsdma
	mov	b,h
	mov	c,l
	mvi	a,BO.SETDMA
	call	bcall
	lda	rswr
	ora	a
	mvi	a,BO.READ
	jz	rsh1
	lda	rssec			; write: the second (odd) half as
	ani	1			; a "directory" write (type 1), so
					; the BIOS writes the sector now
	mov	c,a
	mvi	a,BO.WRITE
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
	mvi	a,BO.SELDSK
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

; The logical host sector of each physical sector (the BIOS's skew is
; 0,4,8,2,6,1,5,9,3,7).
invskw:	db	0,5,3,8,1,6,4,9,2,7

rsdrv:	db	0
rsdma:	dw	0
rstrk:	dw	0
rssec:	db	0
rswr:	db	0			; 0 read, 1 write
rsseen:	db	0			; drives selected already (bit n)
