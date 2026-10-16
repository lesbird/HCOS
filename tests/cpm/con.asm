; con.asm - console: version, tabs, strings, status, direct output,
; IOBYTE, and line input with ^H, rubout and ^U.
; WAIT: READY>
; KEYS: ab\bc\177d\025xy\r

	include	test.inc

TESTMAIN:
	call	PSTR
	db	'{{',13,10,'VER',0
	mvi	c,12
	call	BDOS
	call	PHEXW
	call	PNL
	lxi	d,tabs			; tabs expand to columns 8, 16
	mvi	c,C_WRITESTR
	call	bcall
	mvi	c,C_STAT		; nothing typed
	call	bcall
	call	PA
	mvi	c,C_RAWIO		; direct output
	mvi	e,'*'
	call	bcall
	mvi	c,7			; IOBYTE
	call	bcall
	call	PA
	call	PNL
	call	PSTR
	db	'READY>',0
	lxi	d,buf
	mvi	c,10
	call	bcall
	call	PNL
	call	PSTR
	db	'LINE',0
	lda	buf+1
	call	PA
	lxi	h,buf+2
	lda	buf+1
	mov	b,a
ln1:	mov	a,b
	ora	a
	jz	ln2
	mov	a,m
	call	PA
	inx	h
	dcr	b
	jmp	ln1
ln2:	call	PNL
	call	PSTR
	db	'}}',13,10,0
	jmp	BOOT

tabs:	db	'A',9,'B',9,'C|$'
buf:	db	20,0
	ds	22
