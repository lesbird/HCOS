; hdos30.asm - HDOS 3.0 calls: .CRC16 of "123456789" (FEE8, the
; standard CRC-16) and .GDA of SY (known) and XX (unknown).

	.8080
	include	hdos.inc

	org	USERFWA-8
	ABSHDR	USERFWA,LEN,start

start:	lxi	h,txt
	lxi	d,0
	lxi	b,9
	SCALL	.CRC16
	lxi	h,mcrc
	SCALL	.PRINT
	mov	a,d
	call	hex
	mov	a,e
	call	hex
	lxi	d,'S'+256*'Y'
	SCALL	.GDA
	call	res
	lxi	d,'X'+256*'X'
	SCALL	.GDA
	call	res
	lxi	h,mend
	SCALL	.PRINT
	xra	a
	SCALL	.EXIT

; res - " C=x" (and " A=hh" if CY)
res:	push	psw
	lxi	h,mgda
	SCALL	.PRINT
	pop	psw
	push	psw
	mvi	a,'0'
	aci	0
	SCALL	.SCOUT
	pop	psw
	rnc
	push	psw
	lxi	h,ma
	SCALL	.PRINT
	pop	psw
hex:	push	psw
	rrc
	rrc
	rrc
	rrc
	call	nib
	pop	psw
nib:	ani	0Fh
	adi	90h
	daa
	aci	40h
	daa
	SCALL	.SCOUT
	ret

txt:	db	'123456789'
mcrc:	db	'CRC',' '+200Q
mgda:	db	' GDA C','='+200Q
ma:	db	' A','='+200Q
mend:	db	' HDOS 3.0 OK',212Q
LEN	equ	$-USERFWA
