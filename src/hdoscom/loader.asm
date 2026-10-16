; loader.asm - load an .ABS file

; ldprog - load the program named at HL using the default block at BC
; (normally defabs). Sets pentry and S.USRM, and leaves the file open
; on channel -1 as HDOS does. Returns CY and A = EC.* on error.
ldprog:	lxi	d,ldfcb
	call	parsenm			; name -> FCB
	rc
	lxi	d,ldfcb
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	mvi	a,EC.FNF
	stc
	rz

	; First record: header and the start of the image.
	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS
	lxi	d,ldfcb
	mvi	c,F_READ
	call	BDOS
	ora	a
	jnz	ldbad
	lda	TBUF
	cpi	ABSID
	jnz	ldbad
	lda	TBUF+1
	cpi	ABSTYP
	jnz	ldbad
	lhld	TBUF+6			; entry
	shld	pentry
	lhld	TBUF+2			; load address must be above us
	lxi	d,-HCEND
	dad	d
	jnc	ldmem
	lhld	TBUF+2			; and the end below the BDOS, with
	xchg				; room to read a whole last record
	lhld	TBUF+4
	dad	d
	shld	ldend
	lxi	d,128
	dad	d
	jc	ldmem
	xchg				; DE = end + 128
	lhld	memtop
	call	cmphd			; memtop < end + 128?
	jc	ldmem
	lhld	ldend
	shld	S.USRM

	; Copy the rest of the first record, then read straight into
	; place a record at a time until the image is complete.
	lhld	TBUF+2
	xchg				; DE = load address
	lxi	h,TBUF+ABSHLEN
	mvi	b,128-ABSHLEN
	call	move			; DE advances
ld1:	lhld	ldend			; done when DE >= end
	call	cmphd
	jc	ld2
	jz	ld2
	push	d
	mvi	c,F_DMAOFF
	call	BDOS
	lxi	d,ldfcb
	mvi	c,F_READ
	call	BDOS
	pop	d
	ora	a			; a file shorter than the header
	jnz	ld2			; says loads fine on HDOS too
				; (trailing DS space isn't in it)
	lxi	h,128
	dad	d
	xchg
	jmp	ld1
ld2:	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS
	mvi	a,-1			; channel -1 holds the program file
	call	chptr
	mvi	m,CM.RD
	inx	h
	xchg
	lxi	h,ldfcb
	mvi	b,FCBLEN
	call	move
	xra	a
	ret

ldbad:	mvi	a,EC.IFC		; illegal file contents
	stc
	ret
ldmem:	mvi	a,EC.NEM		; not enough memory
	stc
	ret

; cmphd - compare HL with DE: CY if HL < DE, Z if equal.
cmphd:	mov	a,h
	cmp	d
	rnz
	mov	a,l
	cmp	e
	ret

defabs:	db	'SY0ABS'		; default device and type
pentry:	dw	0			; entry address
ldend:	dw	0			; load address + length
