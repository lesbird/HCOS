; sysgen.asm - SYSGEN.COM: put HCOS on another disk
;
;	SYSGEN d:
;
; Copies the reserved tracks (the boot record, shell, BDOS and BIOS:
; tracks 0-2, 30 sectors) from A: to d:, which must be on the same
; controller as A: (B: or C:), and checks them. The disk on d: keeps its
; own label (bytes 03H-1CH of the boot record).

	include	util.inc

NSEC	equ	30
BUF	equ	1000h		; the reserved tracks, 7.5K
TMP	equ	BUF+NSEC*256

main:	lda	DFCB		; d:
	ora	a
	jz	usage
	dcr	a
	jz	usage		; not A: itself
	cpi	3
	jnc	other		; D:-F: are the other controller's
	sta	dst
	mov	c,a
	call	drvok
	jz	nodrv
	jc	notrdy
	lxi	h,BUF		; read A:'s
	shld	sptr
	xra	a
	sta	src
	call	pass
	jc	rderr
	lda	dst		; d:'s label
	mov	c,a
	mvi	b,0
	mvi	e,0
	lxi	h,TMP
	xra	a
	call	bphys
	jc	rderr
	lxi	h,TMP+3
	lxi	d,BUF+3
	mvi	b,1Ah
lab1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	lab1
	lxi	h,BUF		; write d:'s
	shld	sptr
	lda	dst
	sta	src
	mvi	a,1
	sta	op
	call	pass
	jc	wrerr
	lxi	h,BUF		; and check them
	shld	sptr
	mvi	a,2
	sta	op
	call	pass
	jc	vferr
	lxi	d,mdone
	call	pstr
	lda	dst
	adi	'A'
	call	pch
	mvi	a,':'
	call	pch
	call	crlf
	jmp	BOOT

; pass - the 30 sectors of drive src: op 0 read them to sptr up, 1 write
; them from there, 2 read each to TMP and compare. CY on an error.
pass:	xra	a
	sta	sec
ps1:	lda	sec		; track = sec / 10, sector = sec mod 10
	mvi	b,0
ps2:	sui	10
	jc	ps3
	inr	b
	jmp	ps2
ps3:	adi	10
	mov	e,a
	lda	src
	mov	c,a
	lhld	sptr
	lda	op
	cpi	2
	jnz	ps4
	lxi	h,TMP
	xra	a
ps4:	call	bphys
	rc
	lda	op
	cpi	2
	jnz	ps6
	lhld	sptr		; compare
	lxi	d,TMP
	mvi	b,0
ps5:	ldax	d
	cmp	m
	stc
	rnz
	inx	h
	inx	d
	dcr	b
	jnz	ps5
ps6:	lhld	sptr
	inr	h		; + 256
	shld	sptr
	lxi	h,sec
	inr	m
	mov	a,m
	cpi	NSEC
	jc	ps1
	ora	a
	ret

usage:	lxi	d,musage
	jmp	fail
other:	lxi	d,mother
	jmp	fail
nodrv:	lxi	d,mnodrv
	jmp	fail
notrdy:	lxi	d,mnotr
	jmp	fail
rderr:	lxi	d,mrd
	jmp	fail
wrerr:	lxi	d,mwr
	jmp	fail
vferr:	lxi	d,mvf
fail:	call	pstr
	jmp	BOOT

musage:	db	'SYSGEN d: (B: or C:) - put HCOS from A: on d:',13,10,'$'
mother:	db	'SYSGEN: d: must be on the same controller as A: (B: or C:)'
	db	13,10,'$'
mnodrv:	db	'SYSGEN: no such drive',13,10,'$'
mnotr:	db	'SYSGEN: drive not ready',13,10,'$'
mrd:	db	'SYSGEN: read error',13,10,'$'
mwr:	db	'SYSGEN: write error',13,10,'$'
mvf:	db	'SYSGEN: the copy does not read back the same',13,10,'$'
mdone:	db	'HCOS put on $'

dst:	db	0
src:	db	0
op:	db	0
sec:	db	0
sptr:	dw	0
