; loader.asm - load an .ABS file

; ldprog - load the program named at HL using the default block at BC
; (normally defabs). It is opened on channel -1 and stays open there,
; as on HDOS, so it can come from a CP/M or an HDOS disk. Sets pentry
; and S.USRM. Returns CY and A = EC.* on error.
ldprog:	push	h
	push	b
	mvi	a,-1			; channel -1: let go of what it had
	call	chptr
	mvi	m,CM.CLS
	pop	d
	pop	h
	mvi	a,-1
	call	sopenr
	rc

	; First sector: header and the start of the image.
	lhld	psec
	xchg
	mvi	b,1
	call	chrd
	jc	ldbad
	lhld	psec
	mov	a,m
	cpi	ABSID
	jnz	ldbad
	inx	h
	mov	a,m
	cpi	ABSTYP
	jnz	ldbad
	mvi	a,6			; entry
	call	ldw
	shld	pentry
	mvi	a,2			; load address must be above us
	call	ldw
	shld	ldadr
	lxi	d,-HCEND
	dad	d
	jnc	ldmem
	mvi	a,4			; and the end below the top, with
	call	ldw			; room to read a whole last sector
	xchg
	lhld	ldadr
	dad	d
	jc	ldmem
	shld	ldend
	inr	h
	jz	ldmem
	xchg				; DE = end + 256
	lhld	memtop
	call	cmphd			; memtop < end + 256?
	jc	ldmem
	lhld	ldend
	shld	S.USRM

	; Copy the rest of the first sector, then read straight into
	; place a sector at a time until the image is complete. A file
	; shorter than its header says loads fine on HDOS too (DS space
	; at the end isn't in it).
	lhld	ldadr
	xchg
	lhld	psec
	lxi	b,ABSHLEN
	dad	b
	mvi	b,256-ABSHLEN
	call	move			; DE advances
ld1:	lhld	ldend			; done when DE >= end
	call	cmphd
	jc	ld2
	jz	ld2
	mvi	b,1
	call	chrd			; DE advances
	jnc	ld1
ld2:	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS
	xra	a
	ret

ldbad:	mvi	a,EC.IFC		; illegal file contents
	stc
	ret
ldmem:	mvi	a,EC.NEM		; not enough memory
	stc
	ret

; ldw - HL = word at offset A of the header in psec.
ldw:	lhld	psec
	call	rdadap
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
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
ldadr:	dw	0			; load address
ldend:	dw	0			; load address + length
