; romlib.asm - the H17 ROM's utility library, at the ROM's addresses
;
; Heath's HDOS programs call small utility routines in the H17 disk
; ROM (1800H-1FFFH) directly: $TYPTX, $MOVE, $DADA, $MU86 and so on
; (see the "IN H17 ROM" equates in the HDOS decks). Under CP/M that
; address range is plain RAM, so HDOS.COM provides the routines there,
; each at its ROM entry address and behaving the same way, registers
; and flags included. The ROM's disk code (1992H on) is not included.
;
; Labels are rNAME for $NAME (rNAMEp for $NAME.). Entry addresses
; are from the HDOS decks, written in split octal there
; (e.g. $DADA = 030.072A = 183AH). The assert lines hold them in place.

ROMLIB	equ	1830h

	org	ROMLIB

; 1830H (no name in the decks) - compare C bytes at DE and HL: Z if
; equal. DE, HL advanced to the first difference.
	assert	$ == 1830h
rcomp:	ldax	d
	cmp	m
	rnz
	inx	d
	inx	h
	dcr	c
	jnz	rcomp
	ret

; $DADA - HL = HL + (0,A). CY on overflow. Uses F, H, L.
	assert	$ == 183Ah
rdada:	push	d
	mov	e,a
	mvi	d,0
	dad	d
	pop	d
	ret

; $DADA. - HL = HL + (0,A). Uses A, F, H, L.
	assert	$ == 1841h
rdadap:	add	l
	mov	l,a
	rnc
	inr	h
	ret

; $DU66 - unsigned divide: HL = BC / DE, DE = remainder. Uses all.
	assert	$ == 1846h
rdu66:	mov	a,d			; DE = -divisor
	cma
	mov	d,a
	mov	a,e
	cma
	mov	e,a
	inx	d
	mov	a,d
	ora	e
	jz	du.z			; divide by zero
	xra	a			; A = shift count: line the
du.1:	mov	h,d			; divisor up under the dividend
	mov	l,e
	dad	b
	jnc	du.2
	inr	a
	mov	h,d
	mov	l,e
	dad	h
	xchg
	jc	du.1
	xchg
	dcr	a
du.2:	mov	h,b			; HL = remainder so far,
	mov	l,c			; BC = quotient
	lxi	b,0
du.3:	push	psw
	dad	d			; try subtracting
	jc	du.4
	mov	a,l			; didn't go: add it back
	sub	e
	mov	l,a
	mov	a,h
	sbb	d
	mov	h,a
du.4:	mov	a,c			; shift the result bit in
	ral
	mov	c,a
	mov	a,b
	ral
	mov	b,a
	stc				; halve the (negative) divisor
	mov	a,d
	rar
	mov	d,a
	mov	a,e
	rar
	mov	e,a
	pop	psw
	dcr	a
	jp	du.3
du.z:	xchg
	mov	h,b
	mov	l,c
	ret

; $HLIHL - HL = (HL). Uses A, H, L.
	assert	$ == 1889h
rhlihl:	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	ret

; $CDEHL - Z if DE = HL. Uses A, F.
	assert	$ == 188Eh
rcdehl:	mov	a,e
	xra	l
	rnz
	mov	a,d
	xra	h
	ret

; $CHL - HL = -HL. Uses A, F, H, L.
	assert	$ == 1894h
rchl:	mov	a,h
	cma
	mov	h,a
	mov	a,l
	cma
	mov	l,a
	inx	h
	ret

; $INDL - DE = word at HL + (inline word). Returns past the word.
	assert	$ == 189Ch
rindl:	xthl
	mov	e,m
	inx	h
	mov	d,m
	inx	h
	xthl
	xchg
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	xchg
	ret

; $MOVE - move BC bytes from DE to HL, safe for overlaps. Exit DE, HL
; past the end, NC. Uses all.
	assert	$ == 18AAh
rmove:	mov	a,b
	ora	c
	rz
	mov	a,l			; to a higher address: back to front
	sub	e
	mov	a,h
	sbb	d
	jc	mv.up
	dcx	b
	dad	b
	push	h
	xchg
	dad	b
	push	h
mv.dn:	mov	a,m
	stax	d
	dcx	d
	dcx	h
	dcx	b
	mov	a,b
	ana	a
	jp	mv.dn
	pop	d
	pop	h
	inx	d
	inx	h
	ret
mv.up:	ldax	d			; to a lower address: front to back
	mov	m,a
	inx	h
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	mv.up
	ret

; 18D4H (no name in the decks) - HL = DE * 10, CY on overflow.
	assert	$ == 18D4h
rmu10:	xchg
	dad	h
	rc
	mov	d,h
	mov	e,l
	dad	h
	rc
	dad	h
	rc
	dad	d
	ret

; $MU66 - HL = BC * DE (unsigned). Z if no overflow. Uses all.
	assert	$ == 18DFh
rmu66:	xra	a			; A counts overflows
	push	psw
	lxi	h,0
mu6.1:	mov	a,b			; next multiplier bit
	rar
	mov	b,a
	mov	a,c
	rar
	mov	c,a
	jnc	mu6.2
	dad	d
	jnc	mu6.2
	pop	psw
	inr	a
	push	psw
mu6.2:	mov	a,b
	ora	c
	jz	mu6.3
	xchg
	dad	h
	xchg
	jnc	mu6.1
	pop	psw
	inr	a
	push	psw
	jmp	mu6.1
mu6.3:	pop	psw
	ret

; $MU86 - HL = A * DE (unsigned). Z if no overflow. Uses A, F, H, L.
	assert	$ == 1907h
rmu86:	lxi	h,0
	push	b
mu8.0:	mov	b,h			; B counts overflows
mu8.1:	ora	a
mu8.r:	rar
	jnc	mu8.2
	dad	d
	jnc	mu8.2
	inr	b
mu8.2:	ora	a
	jz	mu8.3
	xchg
	dad	h
	xchg
	jnc	mu8.r
	inr	b
	jmp	mu8.1
mu8.3:	ora	b
	pop	b
	ret

; $RSTALL - pop PSW, BC, DE, HL and return.
	assert	$ == 1927h
rrstall: pop	psw
	pop	b
	pop	d
	pop	h
	ret

; $SAVALL - push HL, DE, BC, PSW under the return address. Uses H, L.
	assert	$ == 192Ch
rsavall: xthl
	push	d
	push	b
	push	psw
	pchl

; $TJMP - jump through the word table after the call, index A.
; $TJMP. takes A = index * 2. Exit A = index * 2.
	assert	$ == 1931h
rtjmp:	rlc
	assert	$ == 1932h
rtjmpp:	xthl
	push	psw
	call	rdadap
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	pop	psw
	xthl
	ret

; $TBRA - branch through the byte table after the call: the byte at
; index A is added to its own address. Uses F, H, L.
	assert	$ == 193Eh
rtbra:	xthl
	push	d
	mov	e,a
	mvi	d,0
	dad	d
	mov	e,m
	dad	d
	pop	d
	xthl
	ret

; 1949H (no name in the decks) - look up key A in the table at HL of
; (key, value) byte pairs ended by a 0 key. Exit HL -> the value byte
; of the matching pair, Z; or of the 0 terminator, NZ and A = 0.
	assert	$ == 1949h
rtbls:	push	b
	mov	b,a
tb.1:	mov	a,m
	cmp	b
	jz	tb.3
	ana	a
	inx	h
	inx	h
	jnz	tb.1
	dcx	h
	dcx	h
	ora	h
	mvi	a,0
tb.3:	pop	b
	inx	h
	ret

; $TYPTX - type the text after the call (last char has bit 7; the
; ROM prints a 0 byte as is, .SCOUT turns NL into CR LF). Uses A, F.
	assert	$ == 195Eh
rtyptx:	xthl
	call	rtyptxp
	xthl
	ret

; $TYPTX. - type the text at HL. Exit HL past it.
	assert	$ == 1964h
rtyptxp: mov	a,m
	ani	7Fh
	SCALL	.SCOUT
	cmp	m
	inx	h
	jz	rtyptxp
	ret

; $UDD - store BC as A decimal digits (zero filled) at HL. Exit HL =
; HL + A. Uses all.
	assert	$ == 196Fh
rudd:	call	rdada
	push	h
ud.1:	push	psw
	push	h
	lxi	d,10
	call	rdu66
	push	h
	pop	b
	pop	h
	mvi	a,'0'
	add	e
	dcx	h
	mov	m,a
	pop	psw
	dcr	a
	jnz	ud.1
	pop	h
	ret

; $ZERO - zero B bytes at HL. Exit A = 0. Uses A, B, F, H, L.
	assert	$ == 198Ah
rzero:	xra	a
zr.1:	mov	m,a
	inx	h
	dcr	b
	jnz	zr.1
	ret

	assert	$ == 1992h
ROMLIBE	equ	$
