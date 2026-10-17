; tshell.asm - phase 1 test shell, in the shell's place at SHELLB
;
; Proves the boot, the console and the clock until the real shell
; comes. Commands:
;   VER   the version
;   TIME  the clock: milliseconds counted since the ROM started it
;         (wraps at 131 s). It starts about 0.9 s after reset
;   WAIT  waits 1 s by the clock, then says so
; Uses only the BIOS.

	.8080
	include	layout.inc

	org	SHELLB

	jmp	cold
	jmp	warm

cold:
warm:	lxi	sp,stack
prompt:	lxi	h,pmsg
	call	print
	call	getln
	lxi	h,cmds		; find the command
next:	mov	a,m
	ora	a
	jz	unknown
	lxi	d,line
cmp:	ldax	d
	cmp	m
	jnz	skip
	inx	d
	inx	h
	ora	a		; both ended
	jnz	cmp
	mov	e,m		; the routine follows the name
	inx	h
	mov	d,m
	xchg
	lxi	d,prompt	; return to the prompt
	push	d
	pchl
skip:	mov	a,m		; to the end of this name
	inx	h
	ora	a
	jnz	skip
	inx	h		; past the routine
	inx	h
	jmp	next

unknown: lda	line
	ora	a
	jz	prompt		; empty line
	lxi	h,qmsg
	call	print
	jmp	prompt

cmds:	db	'VER',0
	dw	ver
	db	'TIME',0
	dw	time
	db	'WAIT',0
	dw	wait
	db	0

ver:	lxi	h,vmsg
	jmp	print

time:	call	B.TICKS
	dad	h		; ticks of 2 ms
	call	pdec
	lxi	h,msmsg
	jmp	print

wait:	call	B.TICKS
	lxi	d,500		; 1 s
	dad	d
	xchg			; DE = when
wt1:	call	B.TICKS
	mov	a,l
	sub	e
	mov	a,h
	sbb	d
	jm	wt1		; until now - when >= 0
	lxi	h,wmsg
	jmp	print

; Read a line into line, uppercased and 0-terminated, with BS/rubout.
getln:	lxi	h,line
gl1:	push	h
	call	B.CONIN
	pop	h
	cpi	0dh
	jz	gl3
	cpi	08h
	jz	gl2
	cpi	7fh
	jz	gl2
	cpi	' '
	jc	gl1
	mov	b,a
	mov	a,l
	cpi	(line+40) and 0ffh
	jz	gl1		; full
	mov	a,b
	cpi	'a'
	jc	gl1a
	cpi	'z'+1
	jnc	gl1a
	sui	20h
gl1a:	mov	m,a
	inx	h
	call	echo
	jmp	gl1
gl2:	mov	a,l		; back a character
	cpi	line and 0ffh
	jz	gl1
	dcx	h
	push	h
	lxi	h,bsmsg
	call	print
	pop	h
	jmp	gl1
gl3:	mvi	m,0
	lxi	h,crlf
	jmp	print

echo:	push	h
	mov	c,a
	call	B.CONOUT
	pop	h
	ret

print:	mov	a,m
	ora	a
	rz
	call	echo
	inx	h
	jmp	print

; Print HL in decimal.
pdec:	lxi	b,-10000
	call	pd1
	lxi	b,-1000
	call	pd1
	lxi	b,-100
	call	pd1
	lxi	b,-10
	call	pd1
	mvi	a,'0'
	add	l
	jmp	echo
pd1:	mvi	a,'0'-1
pd2:	inr	a
	dad	b
	jc	pd2
	push	psw		; undo the last add
	mov	a,l
	sub	c
	mov	l,a
	mov	a,h
	sbb	b
	mov	h,a
	pop	psw
	jmp	echo

pmsg:	db	'A>',0
qmsg:	db	'?',0dh,0ah,0
vmsg:	db	'HCOS 2.0 phase 1 test shell',0dh,0ah,0
msmsg:	db	' ms by the clock',0dh,0ah,0
wmsg:	db	'1 SECOND',0dh,0ah,0
bsmsg:	db	08h,' ',08h,0
crlf:	db	0dh,0ah,0

line:	ds	41
	ds	32
stack:

	assert	$ <= BDOSB
