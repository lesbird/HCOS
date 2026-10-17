; util.inc - what the HCOS utilities share: the BIOS entries they use
; (found from 0001H, so a utility runs on every build), printing, and the
; drive argument.

	.8080
	include	cpm.inc

BO.SELDSK equ	27		; BIOS jump table offsets
BO.PHYS	equ	60		; HCOS: a physical sector (layout.inc)

	org	TPA
	jmp	main

; bphys - B.PHYS: A = 0 read, 1 write; C = drive, B = track, E = sector
; 0-9, HL = 256 bytes. NZ and CY on an error.
bphys:	push	h
	lhld	BOOT+1		; WBOOT, the BIOS + 3
	push	d
	lxi	d,BO.PHYS-3
	dad	d
	pop	d
	xthl
	ret

; drvok - is drive C there (Z: no such drive) and ready (CY: not ready)?
; SELDSK with E = 1 doesn't check; with E = 0 it does, as on a first
; select, and an empty H37 drive must be caught before a read.
drvok:	push	b
	mvi	e,1
	call	bsel
	pop	b
	mov	a,h
	ora	l
	rz
	push	b
	mvi	e,0
	call	bsel
	pop	b
	mov	a,h
	ora	l
	jz	dok1
	ori	1		; NZ, NC: ready
	ret
dok1:	inr	a		; NZ, CY: not ready
	stc
	ret
bsel:	lhld	BOOT+1
	push	d
	lxi	d,BO.SELDSK-3
	dad	d
	pop	d
	pchl

; Print the '$' string at DE; the char in A.
pstr:	mvi	c,C_WRITESTR
	jmp	BDOS
pch:	push	b
	push	d
	push	h
	mov	e,a
	mvi	c,C_WRITE
	call	BDOS
	pop	h
	pop	d
	pop	b
	ret
crlf:	mvi	a,13
	call	pch
	mvi	a,10
	jmp	pch
