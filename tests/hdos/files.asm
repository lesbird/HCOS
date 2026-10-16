; files.asm - file SCALLs: open, read, write, EOF, position, name,
; rename, clear, delete, decode, errors, .ERROR.

	include	test.inc

BUF	equ	4000h

; RES 'label' - print label and the carry/A from the last SCALL.
RES	macro	label
	push	psw
	call	PSTR
	db	label,0
	pop	psw
	call	PRES
	endm

TESTMAIN:
	call	PSTR
	db	'{{',12Q,0

	; Write 3 sectors: sector n is filled with n.
	lxi	h,BUF
	mvi	c,3
	mvi	b,0
fill:	mov	m,b
	inr	l
	jnz	fill
	inr	h
	inr	b
	dcr	c
	jnz	fill
	mvi	a,0
	lxi	h,nf
	lxi	d,defdat
	SCALL	.OPENW
	RES	'OW'
	mvi	a,0
	lxi	b,3*256
	lxi	d,BUF
	SCALL	.WRITE
	RES	' WR'
	mvi	a,0
	SCALL	.CLOSE
	RES	' CL'
	call	PNL

	; Read it back: 1 sector, then ask for 4 (only 2 left).
	mvi	a,1
	lxi	h,nfx			; no extension: default DAT
	lxi	d,defdat
	SCALL	.OPENR
	RES	'OR'
	call	rd1
	mvi	a,1
	lxi	b,4*256
	lxi	d,BUF
	SCALL	.READ
	RES	' RD4'
	call	PSTR
	db	' B=',0
	mov	a,b
	call	PHEX
	call	PSTR
	db	' DE=',0
	xchg
	call	PHEXW
	call	PNL

	; Position to sector 1 and read; then past the end.
	mvi	a,1
	lxi	b,1
	SCALL	.POSIT
	RES	'PO1'
	call	rd1
	mvi	a,1
	lxi	b,7
	SCALL	.POSIT
	RES	' PO7'
	call	PSTR
	db	' BC=',0
	mov	h,b
	mov	l,c
	call	PHEXW
	call	PNL

	; .NAME
	mvi	a,1
	lxi	d,BUF
	lxi	h,BUF+8
	SCALL	.NAME
	RES	'NAME'
	mvi	a,' '
	SCALL	.SCOUT
	lxi	h,BUF
	mvi	b,17
	call	pstrn
	call	PNL

	; Close twice; bad channel; read a closed channel.
	mvi	a,1
	SCALL	.CLOSE
	RES	'CL'
	mvi	a,1
	SCALL	.CLOSE
	RES	' CL'
	mvi	a,9
	lxi	b,256
	lxi	d,BUF
	SCALL	.READ
	RES	' CH9'
	mvi	a,2
	lxi	b,256
	lxi	d,BUF
	SCALL	.READ
	RES	' CH2'
	call	PNL

	; Name errors.
	lxi	h,nnope
	call	tryopen
	RES	'NOPE'
	lxi	h,nbad
	call	tryopen
	RES	' 1BAD'
	lxi	h,nbaddev
	call	tryopen
	RES	' XX:'
	lxi	h,ntt
	call	tryopen
	RES	' TT:'
	mvi	a,2
	SCALL	.CLOSE
	call	PNL

	; Rename; the old name is gone, the new one opens.
	lxi	h,nf
	lxi	d,defdat
	lxi	b,ng
	SCALL	.RENAM
	RES	'RN'
	lxi	h,nf
	call	tryopen
	RES	' OLD'
	lxi	h,ng
	call	tryopen
	RES	' NEW'
	mvi	a,2
	SCALL	.CLOSE
	call	PNL

	; .OPENW then .CLEAR leaves the old file as it was.
	mvi	a,3
	lxi	h,ng
	lxi	d,defdat
	SCALL	.OPENW
	mvi	a,3
	lxi	b,256
	lxi	d,BUF
	SCALL	.WRITE
	mvi	a,3
	SCALL	.CLEAR
	RES	'CLR'
	mvi	a,3
	lxi	h,ng
	lxi	d,defdat
	SCALL	.OPENR
	mvi	a,3
	lxi	b,4*256
	lxi	d,BUF
	SCALL	.READ
	RES	' RD4'
	call	PSTR
	db	' B=',0
	mov	a,b
	call	PHEX
	mvi	a,3
	SCALL	.CLOSE

	; Delete, twice.
	lxi	h,ng
	lxi	d,defdat
	SCALL	.DELET
	RES	' DEL'
	lxi	h,ng
	lxi	d,defdat
	SCALL	.DELET
	RES	' DEL'
	call	PNL

	; .DECODE
	lxi	h,ndec
	lxi	d,defdat
	lxi	b,BUF
	SCALL	.DECODE
	RES	'DEC'
	lxi	h,BUF
	mvi	b,15
dec1:	mvi	a,' '
	SCALL	.SCOUT
	mov	a,m
	call	PHEX
	inx	h
	dcr	b
	jnz	dec1
	call	PNL

	; .ERROR
	mvi	a,EC.FNF
	mvi	h,'|'
	SCALL	.ERROR
	mvi	a,EC.EOF
	mvi	h,12Q
	SCALL	.ERROR

	call	PSTR
	db	'}}',12Q,0
	xra	a
	SCALL	.EXIT

; Read one sector on channel 1 and print " RD C=x [first byte]".
rd1:	mvi	a,1
	lxi	b,256
	lxi	d,BUF
	SCALL	.READ
	RES	' RD'
	mvi	a,' '
	SCALL	.SCOUT
	lda	BUF
	call	PHEX
	ret

; .OPENR channel 2 on the name at HL, default DAT.
tryopen: mvi	a,2
	lxi	d,defdat
	SCALL	.OPENR
	ret

; Print B bytes at HL, zeros as '_'.
pstrn:	mov	a,m
	ora	a
	jnz	ps1
	mvi	a,'_'
ps1:	SCALL	.SCOUT
	inx	h
	dcr	b
	jnz	pstrn
	ret

defdat:	db	'SY0DAT'
nf:	db	'TESTF.DAT',0
nfx:	db	'testf',0
ng:	db	'TESTG.DAT',0
nnope:	db	'NOPE',0
nbad:	db	'1BAD',0
nbaddev: db	'XX:A',0
ntt:	db	'TT:',0
ndec:	db	'SY0:Abc.x',0

TESTLEN	equ	$-USERFWA
