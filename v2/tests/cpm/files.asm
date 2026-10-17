; files.asm - the file system: make, sequential write across extents,
; close, open, read to the end, size, random read and write (sparse,
; into module 1, zero fill), rename, attributes, delete, search, user
; numbers, disk vectors and the DPB.

	include	test.inc

FCB	equ	DFCB

; FNAME 'NAME    EXT' - FCB = drive 0, that name, the rest zero.
FNAME	macro	nm
	call	setf
	db	nm
	endm

TESTMAIN:
	call	PSTR
	db	'{{',13,10,0
	lxi	d,BUF
	mvi	c,F_DMAOFF
	call	bcall
	FNAME	'TEST????DAT'		; start clean
	mvi	c,F_DELETE
	call	fcbcall

	; Make and write 200 records (two extents): record n holds n.
	FNAME	'TEST1   DAT'
	mvi	c,F_MAKE
	call	fcbcall
	call	PSTR
	db	'MK',0
	call	PA
	mvi	b,0
wr1:	mov	a,b
	call	fillbuf
	mvi	c,F_WRITE
	call	fcbcall
	ora	a
	jnz	wr2
	inr	b
	mov	a,b
	cpi	200
	jnz	wr1
wr2:	call	PSTR
	db	' WR',0
	call	PA
	mov	a,b
	call	PA
	mvi	c,F_CLOSE
	call	fcbcall
	call	PSTR
	db	' CL',0
	call	PA
	call	PNL

	; Open and read it all back.
	FNAME	'TEST1   DAT'
	mvi	c,F_OPEN
	call	fcbcall
	call	PSTR
	db	'OP',0
	call	PA
	lda	FCB+15			; record count
	call	PA
	mvi	b,0
	mvi	c,0			; C = mismatches
rd1:	push	b
	mvi	c,F_READ
	call	fcbcall
	pop	b
	ora	a
	jnz	rd2
	lda	BUF
	cmp	b
	jz	rd1a
	inr	c
rd1a:	inr	b
	jmp	rd1
rd2:	push	psw
	call	PSTR
	db	' RD',0
	pop	psw
	call	PA
	mov	a,b
	call	PA
	mov	a,c
	call	PA
	lda	FCB+12			; extent now
	call	PA
	call	size
	call	PNL

	; Random: read 150; write 5000 (module 1); size; read 4000
	; (nothing there) and 5000.
	lxi	h,150
	call	rread
	lxi	h,5000
	mvi	a,55h
	call	rwrite
	call	size
	call	PNL
	lxi	h,4000
	call	rread
	lxi	h,5000
	call	rread
	lxi	h,250			; past the end of extent 1's data
	call	rread
	call	PNL

	; Write random with zero fill at 300, then read 301 (same block).
	lxi	h,300
	shld	FCB+33
	mvi	a,77h
	call	fillbuf
	mvi	c,40
	call	fcbcall
	call	PSTR
	db	'ZF',0
	call	PA
	lxi	h,301
	call	rread
	; f36: random record from the position
	mvi	c,36
	call	fcbcall
	lhld	FCB+33
	call	PSTR
	db	' SR',0
	call	PHEXW
	mvi	c,F_CLOSE
	call	fcbcall
	call	PA
	call	PNL

	; Rename, open the old name, R/O attribute, search, delete.
	FNAME	'TEST1   DAT'
	lxi	h,nm2
	lxi	d,FCB+16
	mvi	b,12
	call	movb
	mvi	c,F_RENAME
	call	fcbcall
	call	PSTR
	db	'RN',0
	call	PA
	FNAME	'TEST1   DAT'
	mvi	c,F_OPEN
	call	fcbcall
	call	PA
	FNAME	'TEST2   DAT'
	lda	FCB+9
	ori	80h
	sta	FCB+9
	mvi	c,30
	call	fcbcall
	call	PSTR
	db	' AT',0
	call	PA
	FNAME	'TEST?   DA?'
	mvi	c,F_SFIRST
	call	fcbcall
	call	PSTR
	db	' SF',0
	call	PA
	rrc				; its T1 byte in the DMA buffer
	rrc
	rrc
	lxi	h,BUF+9
	call	dadhl
	mov	a,m
	call	PA
	FNAME	'TEST2   DAT'
	mvi	c,30			; clear R/O again, delete
	call	fcbcall
	mvi	c,F_DELETE
	call	fcbcall
	call	PSTR
	db	' DE',0
	call	PA
	mvi	c,F_DELETE
	call	fcbcall
	call	PA
	call	PNL

	; Search *.COM: how many, and the first.
	FNAME	'????????COM'
	mvi	c,F_SFIRST
	call	fcbcall
	mvi	b,0
sc1:	cpi	0FFh
	jz	sc2
	inr	b
	mvi	c,F_SNEXT
	call	fcbcall
	jmp	sc1
sc2:	call	PSTR
	db	'COM FILES',0
	mov	a,b
	call	PA
	call	PNL

	; User numbers.
	mvi	c,32
	mvi	e,3
	call	bcall
	FNAME	'U3      DAT'
	mvi	c,F_MAKE
	call	fcbcall
	mvi	c,F_CLOSE
	call	fcbcall
	mvi	c,32
	mvi	e,0FFh
	call	bcall
	call	PSTR
	db	'USER',0
	call	PA
	mvi	c,32
	mvi	e,0
	call	bcall
	FNAME	'U3      DAT'
	mvi	c,F_OPEN
	call	fcbcall
	call	PA
	mvi	c,32
	mvi	e,3
	call	bcall
	FNAME	'U3      DAT'
	mvi	c,F_DELETE
	call	fcbcall
	call	PA
	mvi	c,32
	mvi	e,0
	call	bcall
	call	PNL

	; Disk vectors and the DPB.
	call	PSTR
	db	'LOG',0
	mvi	c,24
	call	BDOS
	call	PHEXW
	call	PSTR
	db	' CUR',0
	mvi	c,25
	call	bcall
	call	PA
	call	PSTR
	db	' RO',0
	mvi	c,29
	call	BDOS
	call	PHEXW
	call	PSTR
	db	' DPB',0
	mvi	c,31
	call	BDOS
	mvi	b,15
dp1:	mov	a,m
	call	PHEX
	inx	h
	dcr	b
	jnz	dp1
	call	PNL
	call	PSTR
	db	'ALV',0
	mvi	c,27
	call	BDOS
	mvi	b,12
av1:	mov	a,m
	call	PA
	inx	h
	dcr	b
	jnz	av1
	call	PNL
	call	PSTR
	db	'}}',13,10,0
	jmp	BOOT

; setf - FCB = drive 0 + the 11 bytes after the call, rest zero.
setf:	lxi	h,FCB
	mvi	b,36
sf1:	mvi	m,0
	inx	h
	dcr	b
	jnz	sf1
	pop	h
	lxi	d,FCB+1
	mvi	b,11
	call	movb
	pchl

movb:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	movb
	ret

; fcbcall - BDOS function C on FCB. Keeps B.
fcbcall: push	b
	lxi	d,FCB
	call	BDOS
	pop	b
	ret

; fillbuf - fill BUF with A.
fillbuf: lxi	h,BUF
	mvi	c,128
fb1:	mov	m,a
	inx	h
	dcr	c
	jnz	fb1
	ret

; size - print " SZ" and the file size r2 r1 r0.
size:	mvi	c,35
	call	fcbcall
	call	PSTR
	db	' SZ',0
	lda	FCB+35
	call	PA
	lhld	FCB+33
	mvi	a,' '
	call	PCHR
	jmp	PHEXW

; rread - random read of record HL: print " Rnnnn A byte".
rread:	shld	FCB+33
	push	h
	call	PSTR
	db	' R',0
	pop	h
	call	PHEXW
	xra	a
	call	fillbuf
	mvi	c,F_READRAND
	call	fcbcall
	call	PA
	lda	BUF
	jmp	PA

; rwrite - random write of record HL, filled with A.
rwrite:	shld	FCB+33
	call	fillbuf
	call	PSTR
	db	' W',0
	mvi	c,F_WRITERAND
	call	fcbcall
	jmp	PA

dadhl:	add	l
	mov	l,a
	rnc
	inr	h
	ret

nm2:	db	0,'TEST2   DAT'
BUF	equ	1000h
