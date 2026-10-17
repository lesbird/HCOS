; tshell.asm - phase 1 test shell, in the shell's place at SHELLB
;
; Proves the boot, the console and the clock until the real shell
; comes. Commands:
;   VER   the version
;   TIME  the clock: milliseconds counted since the ROM started it
;         (wraps at 131 s). It starts about 0.9 s after reset
;   WAIT  waits 1 s by the clock, then says so
;   SUM d       reads every record of drive d (A-C) through the BIOS and
;               prints two 16-bit Fletcher sums, in logical record order
;   FILL d tt   writes a pattern over track tt, as a new block (write
;               type 2, then 0)
;   HALF d tt   writes another pattern over the even records of track tt
;               (type 0: the odd halves of each host sector must survive)
;   DIRW d tt   writes record 5 of track tt as a directory write (type 1)
; tests/h17img.py computes what each should give. Uses only the BIOS.

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
	db	'SUM',0
	dw	sum
	db	'FILL',0
	dw	fill
	db	'HALF',0
	dw	half
	db	'DIRW',0
	dw	dirw
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

; ---- Disk tests ----

; Select the drive named by the first argument. Returns to the prompt
; with "?" if there's no such drive.
seldrv:	lhld	argp
	mov	a,m
	sui	'A'
	mov	c,a
	call	B.SELDSK
	mov	a,h
	ora	l
	rnz
	pop	h		; drop our caller
	lxi	h,qmsg
	jmp	print

; The track: the 2 decimal digits after the drive letter, into C.
gettrk:	lhld	argp
	inx	h
	inx	h
	mov	a,m
	sui	'0'
	mov	b,a
	add	a		; x 10
	add	a
	add	b
	add	a
	mov	b,a
	inx	h
	mov	a,m
	sui	'0'
	add	b
	mov	c,a
	sta	trk
	jmp	B.SETTRK

sum:	call	seldrv
	lxi	h,0
	shld	s1
	shld	s2
	xra	a
	sta	trk
sum1:	lda	trk
	mov	c,a
	mvi	b,0
	call	B.SETTRK
	xra	a
	sta	rec
sum2:	call	rdrec
	ora	a
	jnz	rderr
	lxi	h,buf
	mvi	b,128
sum3:	push	h
	mov	e,m
	mvi	d,0
	lhld	s1
	dad	d
	shld	s1
	xchg
	lhld	s2
	dad	d
	shld	s2
	pop	h
	inx	h
	dcr	b
	jnz	sum3
	lxi	h,rec
	inr	m
	mov	a,m
	cpi	20
	jc	sum2
	lxi	h,trk
	inr	m
	mov	a,m
	cpi	40
	jc	sum1
	lxi	h,summsg
	call	print
	lhld	s1
	call	phex
	mvi	a,' '
	call	echo
	lhld	s2
	call	phex
	lxi	h,crlf
	jmp	print

rdrec:	lda	rec
	mov	c,a
	mvi	b,0
	call	B.SETSEC
	lxi	b,buf
	call	B.SETDMA
	jmp	B.READ

rderr:	lxi	h,rdmsg
rwerr:	call	print
	lda	trk
	mov	l,a
	mvi	h,0
	call	pdec
	mvi	a,' '
	call	echo
	lda	rec
	mov	l,a
	mvi	h,0
	call	pdec
	lxi	h,crlf
	jmp	print

; Write record rec from buf, type C.
wrrec:	push	b
	lda	rec
	mov	c,a
	mvi	b,0
	call	B.SETSEC
	lxi	b,buf
	call	B.SETDMA
	pop	b
	jmp	B.WRITE

; buf := (rec * 16 + i + trk) xor E, for i = 0-127.
pattern: lda	rec
	add	a
	add	a
	add	a
	add	a
	lxi	h,trk
	add	m
	lxi	h,buf
	mvi	b,128
pat1:	mov	d,a
	xra	e
	mov	m,a
	mov	a,d
	inr	a
	inx	h
	dcr	b
	jnz	pat1
	ret

fill:	call	seldrv
	call	gettrk
	xra	a
	sta	rec
fill1:	mvi	e,0
	call	pattern
	mvi	c,2		; the first record of a new block
	lda	rec
	ora	a
	jz	fill2
	mvi	c,0
fill2:	call	wrrec
	ora	a
	jnz	wrerr
	lxi	h,rec
	inr	m
	mov	a,m
	cpi	20
	jc	fill1
	ret

half:	call	seldrv
	call	gettrk
	xra	a
	sta	rec
half1:	mvi	e,55h
	call	pattern
	mvi	c,0
	call	wrrec
	ora	a
	jnz	wrerr
	lxi	h,rec
	inr	m
	inr	m
	mov	a,m
	cpi	20
	jc	half1
	ret

dirw:	call	seldrv
	call	gettrk
	mvi	a,5
	sta	rec
	lxi	h,buf		; buf := i + A0H
	mvi	b,128
	mvi	a,0a0h
dw1:	mov	m,a
	inr	a
	inx	h
	dcr	b
	jnz	dw1
	mvi	c,1
	call	wrrec
	ora	a
	rz
wrerr:	lxi	h,wrmsg
	jmp	rwerr

; Print HL in hex.
phex:	mov	a,h
	call	phex2
	mov	a,l
phex2:	push	psw
	rrc
	rrc
	rrc
	rrc
	call	phex1
	pop	psw
phex1:	ani	0fh
	adi	'0'
	cpi	'9'+1
	jc	echo
	adi	7
	jmp	echo

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
	lxi	h,line		; the first space ends the command
gl4:	mov	a,m
	inx	h
	ora	a
	jz	gl5
	cpi	' '
	jnz	gl4
	dcx	h
	mvi	m,0
	inx	h
gl5:	shld	argp		; the arguments
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
summsg:	db	'SUM ',0
rdmsg:	db	'READ ERROR ',0
wrmsg:	db	'WRITE ERROR ',0

argp:	ds	2
trk:	ds	1
rec:	ds	1
s1:	ds	2
s2:	ds	2
buf:	ds	128

line:	ds	41
	ds	32
stack:

	assert	$ <= BDOSB
