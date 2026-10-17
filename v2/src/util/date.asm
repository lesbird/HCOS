; date.asm - DATE.COM: show or set the date HDOS programs see
;
;	DATE		show it
;	DATE dd-Mmm-yy	set it
;
; The H89 has no clock, so the date is kept in A:HDOS.COM and
; A:HDOSFS.COM themselves: a block at offset 3 of each ('HCDT', then
; 'dd-Mmm-yy', then the coded date yyyyyyy mmmm ddddd, years from 1970).
; HDOS programs get it in S.DATE and S.DATC, and new HDOS files get it,
; from the next program on. If the HDOS extension is in memory, its date
; is set too.

	include	util.inc

TAIL	equ	TBUF

main:	lxi	h,TAIL		; the argument, after blanks
	mov	b,m
	inx	h
mn1:	mov	a,b
	ora	a
	jz	show
	mov	a,m
	cpi	' '
	jnz	mn2
	inx	h
	dcr	b
	jmp	mn1
mn2:	call	parse		; HL -> dd-Mmm-yy
	jc	bad
	lxi	h,nhdos		; set it in both files
	call	patch
	jc	nofile
	lxi	h,nhdosx
	call	patch
	lhld	BDOS+1		; the extension in memory?
	mvi	l,0
	push	h
	lxi	d,3
	dad	d
	lxi	d,kxsig
	mvi	b,4
mn3:	ldax	d
	cmp	m
	jnz	mn4
	inx	h
	inx	d
	dcr	b
	jnz	mn3
	pop	h
	lxi	d,16		; KX.DATE
	dad	d
	push	h
	lhld	coded
	xchg
	pop	h
	mov	m,e
	inx	h
	mov	m,d
	push	h
mn4:	pop	h
show:	lxi	h,nhdos		; show A:HDOS.COM's
	call	opnrd
	jc	nofile
	lxi	h,BUF+7
	mvi	b,9
sh1:	mov	a,m
	call	pch
	inx	h
	dcr	b
	jnz	sh1
	call	crlf
	jmp	BOOT

; parse - HL -> 'dd-Mmm-yy': the string (fixed up: 'Mmm') into datstr,
; the coded date into coded. CY if it isn't a date.
parse:	call	dig2		; day, 1-31
	rc
	ora	a
	stc
	rz
	cpi	32
	cmc
	rc
	sta	day
	mov	a,m
	cpi	'-'
	stc
	rnz
	inx	h
	push	h		; month: one of the names
	mov	a,m		; (any case: Mmm)
	call	upper
	sta	datstr+3
	inx	h
	mov	a,m
	call	lower
	sta	datstr+4
	inx	h
	mov	a,m
	call	lower
	sta	datstr+5
	pop	h
	inx	h
	inx	h
	inx	h
	push	h
	lxi	d,months
	mvi	c,1
pm1:	lxi	h,datstr+3
	ldax	d
	ora	a
	jz	pm9		; not a month
	cmp	m
	jnz	pm2
	inx	d
	inx	h
	ldax	d
	cmp	m
	jnz	pm3
	inx	d
	inx	h
	ldax	d
	cmp	m
	jnz	pm4
	jmp	pm5
pm2:	inx	d
pm3:	inx	d
pm4:	inx	d
	inr	c
	jmp	pm1
pm9:	pop	h
	stc
	ret
pm5:	pop	h
	mov	a,c
	sta	month
	mov	a,m
	cpi	'-'
	stc
	rnz
	inx	h
	call	dig2		; year: 70-99 are 19xx, 00-69 20xx
	rc
	cpi	70
	jnc	py1
	adi	100
py1:	sui	70
	sta	year
	lda	day		; the string
	call	two
	shld	datstr
	lda	year
	adi	70
	cpi	100
	jc	py2
	sui	100
py2:	call	two
	shld	datstr+7
	mvi	a,'-'
	sta	datstr+2
	sta	datstr+6
	lda	year		; coded: year << 9 + month << 5 + day
	add	a
	mov	h,a
	lda	month
	rrc
	rrc
	rrc
	mov	l,a
	ani	1
	ora	h
	mov	h,a
	mov	a,l
	ani	0E0h
	mov	l,a
	lda	day
	ora	l
	mov	l,a
	shld	coded
	ora	a
	ret

; two - HL = A as two ASCII digits (L the tens).
two:	mvi	l,'0'-1
tw1:	inr	l
	sui	10
	jnc	tw1
	adi	'0'+10
	mov	h,a
	ret

; dig2 - A = the two decimal digits at HL; HL past them. CY if not.
dig2:	mov	a,m
	sui	'0'
	cpi	10
	cmc
	rc
	mov	b,a
	add	a
	add	a
	add	b
	add	a
	mov	b,a
	inx	h
	mov	a,m
	sui	'0'
	cpi	10
	cmc
	rc
	add	b
	inx	h
	ora	a
	ret

upper:	cpi	'a'
	rc
	cpi	'z'+1
	rnc
	sui	20h
	ret
lower:	cpi	'A'
	rc
	cpi	'Z'+1
	rnc
	adi	20h
	ret

; patch - put the date into record 0 of the file named at HL (11 bytes,
; on A:), offset 3. CY if it isn't there or isn't one of ours.
patch:	call	opnrd
	rc
	lxi	h,datstr
	lxi	d,BUF+7
	mvi	b,9
pa1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	pa1
	lhld	coded
	shld	BUF+16
	lxi	d,FCB
	mvi	c,F_WRITERAND
	call	BDOS
	ora	a
	stc
	rnz
	lxi	d,FCB
	mvi	c,F_CLOSE
	call	BDOS
	ora	a
	ret

; opnrd - open the file named at HL on A: and read record 0 into BUF.
; CY if it isn't there or doesn't start with our date block.
opnrd:	lxi	d,FCB
	mvi	a,1		; A:
	stax	d
	inx	d
	mvi	b,11
op1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	op1
	xra	a
	mvi	b,36-12
op2:	stax	d
	inx	d
	dcr	b
	jnz	op2
	lxi	d,FCB
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	stc
	rz
	lxi	d,BUF
	mvi	c,F_DMAOFF
	call	BDOS
	lxi	d,FCB		; record 0 (FCB+33..35 = 0)
	mvi	c,F_READRAND
	call	BDOS
	ora	a
	stc
	rnz
	lxi	h,BUF+3
	lxi	d,kxdt
	mvi	b,4
op3:	ldax	d
	cmp	m
	stc
	rnz
	inx	h
	inx	d
	dcr	b
	jnz	op3
	ora	a
	ret

bad:	lxi	d,mbad
	call	pstr
	jmp	BOOT
nofile:	lxi	d,mnof
	call	pstr
	jmp	BOOT

mbad:	db	'DATE dd-Mmm-yy, for example DATE 17-Oct-86',13,10,'$'
mnof:	db	'DATE: no A:HDOS.COM (or not an HCOS one)',13,10,'$'
nhdos:	db	'HDOS    COM'
nhdosx:	db	'HDOSFS  COM'
kxdt:	db	'HCDT'
kxsig:	db	'HCKX'
months:	db	'JanFebMarAprMayJunJulAugSepOctNovDec',0
datstr:	db	'01-Jan-80'
day:	db	0
month:	db	0
year:	db	0
coded:	dw	0
FCB:	ds	36
BUF:	ds	128
