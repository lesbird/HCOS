; drives.asm - DRIVES.COM: what is in each drive
;
;	A: H17 0  CP/M
;	B: H17 1  HDOS  SYSTEM DISK
;	C: H17 2  not ready
;	D: H37 0  ...
;
; A:-C: are on the boot controller, D:-F: (in the H17/H37 builds) on the
; other one; SW501 says which booted. An HDOS disk is told by its label
; (track 0, sector 9), and its label text is shown.

	include	util.inc

GPP	equ	0F2h		; SW501
SW.PRI	equ	10h		; booted from the H37 (at 170Q)
LAB.PSS	equ	0Eh		; HDOS label: physical sector size
LAB.SPT	equ	4Fh		; sectors a track
LAB.LAB	equ	11h		; the label text
BUF	equ	1000h

main:	xra	a
	sta	drv
dr1:	lda	drv
	mov	c,a
	call	drvok
	jz	BOOT		; no more drives
	push	psw
	lda	drv		; "A: H17 0  "
	adi	'A'
	call	pch
	lxi	d,mcol
	call	pstr
	in	GPP		; which controller
	ani	SW.PRI
	mov	b,a
	lda	drv
	cpi	3
	jc	dr2
	mov	a,b
	xri	SW.PRI
	mov	b,a
dr2:	lxi	d,mh17
	mov	a,b
	ora	a
	jz	dr3
	lxi	d,mh37
dr3:	call	pstr
	lda	drv
	cpi	3
	jc	dr4
	sui	3
dr4:	adi	'0'
	call	pch
	lxi	d,msp
	call	pstr
	pop	psw
	lxi	d,mnotr
	jc	dr8
	lda	drv		; the HDOS label?
	mov	c,a
	lxi	b,0
	mov	c,a
	mvi	e,9
	lxi	h,BUF
	xra	a
	call	bphys
	lxi	d,mrderr
	jc	dr8
	lxi	d,mcpm
	lda	BUF+LAB.PSS
	ora	a
	jnz	dr8
	lda	BUF+LAB.PSS+1
	cpi	1
	jnz	dr8
	lda	BUF+LAB.SPT
	cpi	10
	jnz	dr8
	lxi	d,mhdos
	call	pstr
	lxi	h,BUF+LAB.LAB	; the label text, as far as it's printable
	mvi	b,40
dr5:	mov	a,m
	cpi	' '
	jc	dr9
	cpi	7Fh
	jnc	dr9
	call	pch
	inx	h
	dcr	b
	jnz	dr5
	jmp	dr9
dr8:	call	pstr
dr9:	call	crlf
	lxi	h,drv
	inr	m
	jmp	dr1

mcol:	db	': $'
mh17:	db	'H17 $'
mh37:	db	'H37 $'
msp:	db	'  $'
mnotr:	db	'not ready$'
mrderr:	db	'read error$'
mcpm:	db	'CP/M$'
mhdos:	db	'HDOS  $'
drv:	db	0
