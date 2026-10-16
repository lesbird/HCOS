; main.asm - start-up, exit and HDOS.COM's own data

; ---- Start-up ----

start:	lxi	sp,hcstk
	lhld	BDOS+1			; the high buffers go just below the
	mvi	l,0			; BDOS, and programs get the rest
	lxi	d,-HISIZE
	dad	d
	shld	memtop
	shld	hibase
	lxi	d,HI.SCR		; and point at each buffer
	call	hiptr
	shld	psscr
	lxi	d,HI.SEC
	call	hiptr
	shld	psec
	lxi	d,HI.GRT
	call	hiptr
	shld	pgrt
	lxi	d,HI.KBUF
	call	hiptr
	shld	pkbuf
	lxi	d,HI.CHT
	call	hiptr
	shld	pchtab
	call	cinit			; console state
	call	finit			; channel table
	call	uinit			; units: format not known yet

	; Copy the command tail out of TBUF, which disk reads reuse.
	lxi	h,TBUF
	lxi	d,cmdbuf
	mvi	b,128
	call	move
	; First word of the command tail is the program name, the rest
	; (with its leading blank) is passed to the program.
	lxi	h,cmdbuf
	mov	c,m			; length
	inx	h
	mvi	b,0
	push	h
	dad	b
	mvi	m,0			; terminate the tail
	pop	h
st1:	mov	a,m			; skip blanks
	cpi	' '
	jnz	st2
	inx	h
	jmp	st1
st2:	ora	a
	jz	usage
	cpi	'/'			; /T: trace
	jnz	st2a
	inx	h
	mov	a,m
	cpi	'T'
	jnz	usage
	sta	trace
	inx	h
	jmp	st1
st2a:	shld	pname
st3:	mov	a,m			; find the end of the name
	ora	a
	jz	st4
	cpi	' '
	jz	st4
	inx	h
	jmp	st3
st4:	shld	pargs			; args start at the blank (or NUL)
	mov	a,m
	mvi	m,0			; terminate the name
	shld	pnend
	sta	pnchr

	call	sysinit			; system area and page zero

	lhld	pname
	lxi	b,defabs
	call	ldprog			; load it; HL = entry, or CY
	jc	ldfail
	lhld	pnend			; put back the char after the name
	lda	pnchr
	mov	m,a
	lhld	pargs
	jmp	launch			; args below STACK, run it

usage:	lxi	d,musage
	mvi	c,C_WRITESTR
	call	BDOS
	jmp	BOOT

; Loading failed with A = HDOS error code: report it and quit.
ldfail:	push	psw
	lxi	d,mnoload
	mvi	c,C_WRITESTR
	call	BDOS
	pop	psw
	call	perror
	jmp	hexit

musage:	db	'HDOS.COM - run an HDOS program: HDOS NAME [args]',0dh,0ah,'$'
mnoload: db	'HDOS: can''t load program: $'

; ---- Exit ----

; Every way out of an HDOS program ends here: close channels, put
; page zero back and warm boot.
hexit:	lxi	sp,hcstk
	call	clsall
	call	sysdone
	jmp	BOOT

; hiptr - HL = hibase + DE.
hiptr:	lhld	hibase
	dad	d
	ret

; ---- Data ----

memtop:	dw	0			; top of program memory (= hibase)
hibase:	dw	0			; high buffers, below the BDOS
psscr:	dw	0			; -> scratch area (S.SCR)
psec:	dw	0			; -> sector buffer
pgrt:	dw	0			; -> GRT of unit 0 (then 1, 2, 3)
pkbuf:	dw	0			; -> type-ahead
pchtab:	dw	0			; -> channel table
pname:	dw	0			; program name in the command tail
pnend:	dw	0			; end of the name
pnchr:	db	0			; char that was at the end of the name
pargs:	dw	0			; arguments
trace:	db	0			; <>0: trace SCALLs
