; tpa.asm - print the TPA top: "TPA hhhh", the address at 0006H.

	.8080
	include	cpm.inc

	org	TPA
	lxi	d,msg
	mvi	c,C_WRITESTR
	call	BDOS
	lda	BDOS+2
	call	hex2
	lda	BDOS+1
	call	hex2
	jmp	BOOT

hex2:	push	psw
	rrc
	rrc
	rrc
	rrc
	call	hex1
	pop	psw
hex1:	ani	0Fh
	adi	'0'
	cpi	'9'+1
	jc	hex3
	adi	7
hex3:	mov	e,a
	mvi	c,C_WRITE
	jmp	BDOS

msg:	db	'TPA $'
