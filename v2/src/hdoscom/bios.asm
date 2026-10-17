; bios.asm - raw sector reads and writes for the HDOS file system
;
; HDOS sector n is physical sector n mod 10 of track n/10, on an H17 or
; an H37 disk alike. The HCOS v2 BIOS's B.PHYS reads and writes it as it
; is on the disk, past the CP/M skew and deblocking, without changing
; the BDOS's selection. (Version 1, on the Heath BIOS, went through
; SETTRK/SETSEC/READ with records 1-20.)
;
; udet still selects a drive in the BIOS to see its DPB; bdsel then
; selects the BDOS's drive again, as the BDOS doesn't expect the BIOS's
; selection to change under it.

BO.SELDSK equ	27		; BIOS jump table offsets
BO.SETTRK equ	30
BO.SETSEC equ	33
BO.SETDMA equ	36
BO.READ	equ	39
BO.WRITE	equ	42
BO.PHYS	equ	60

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
	push	d
	mov	b,h			; track = n / 10, sector = n mod 10
	mov	c,l
	lxi	d,10
	call	rdu66			; HL = track, DE = sector
	mov	b,l
	lda	rsdrv
	mov	c,a
	pop	h
	lda	rswr
	call	bphys
	ora	a
	rz
	lda	rswr
	ora	a
	mvi	a,EC.RF
	stc
	rz
	mvi	a,EC.WF
	stc
	ret

; bphys - the BIOS's B.PHYS, with A, BC, DE and HL as it takes them.
bphys:	push	h
	lhld	BOOT+1			; WBOOT entry, base + 3
	push	d
	lxi	d,BO.PHYS-3
	dad	d
	pop	d
	xthl
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

rsdrv:	db	0
rswr:	db	0			; 0 read, 1 write
rsseen:	db	0			; drives selected already (bit n)
