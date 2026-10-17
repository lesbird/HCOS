; slotldr.inc - the front of H17.COM and H37.COM: copy the driver (img,
; assembled for SLOTB, up to slend) into the BIOS's slot with interrupts
; off (the clock and RST 4 call into the slot), start it, and say so
; (msg). The H17/H37 BIOS has the shell run it at cold boot when SW501
; says the other controller is there.

	if	SLOTS
	di
	lxi	h,img
	lxi	d,SLOTB
	lxi	b,slend-SLOTB
sll1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	sll1
	call	SL.INIT
	ei
	lxi	d,msg
	else
	lxi	d,mno
	endif
	mvi	c,C_WRITESTR
	jmp	BDOS

mno:	db	'This HCOS has no second controller',13,10,'$'
