; syndir.asm - DIRECT.SYS for a CP/M disk, made up for HDOS programs
; (see hdosfs.asm)

; synopen - open DIRECT.SYS of CP/M unit dunit on chp.
synopen: call	hstate
	lda	dunit
	mov	m,a
	mvi	a,HC.POS
	call	hfld
	xra	a
	mov	m,a
	inx	h
	mov	m,a
	mvi	a,CM.SYN
	jmp	setmode

; synpos - position before sector BC.
synpos:	call	hstate
	mvi	a,HC.POS
	call	hfld
	mov	m,c
	inx	h
	mov	m,b
	xra	a
	ret

; synrd - read B sectors of the made-up directory into DE.
synrd:	mov	a,b
	ora	a
	rz
	push	b
	push	d
	call	hstate
	mvi	a,HC.UNIT
	call	hfld
	mov	a,m
	sta	dunit
	mvi	a,HC.POS
	call	hfld
	mov	e,m
	inx	h
	mov	d,m
	inx	d			; next time, the next sector
	mov	m,d
	dcx	h
	mov	m,e
	dcx	d
	xchg				; HL = sector: block = HL/2
	ora	a
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	mvi	a,0
	ral
	sta	synhalf
	xchg				; DE = block
	lhld	synblk			; made already?
	call	cmphd
	jnz	sr1
	lda	synunit
	lxi	h,dunit
	cmp	m
	jz	sr2
sr1:	xchg
	call	synbld
	jc	sr.eof
sr2:	lhld	psec			; copy the half asked for
	lda	synhalf
	add	h
	mov	h,a
	pop	d
	mvi	b,0
	call	move			; 256 bytes, DE advances
	pop	b
	dcr	b
	jmp	synrd
sr.eof:	pop	d
	pop	b
	mvi	a,EC.EOF
	stc
	ret

; synbld - build block HL of unit dunit's made-up directory in psec,
; and its GRT. CY if there is no such block.
synbld:	shld	synblk
	lda	dunit
	sta	synunit
	lhld	psec			; clear the block
	lxi	b,512
	call	zfill
	lxi	h,tmpfcb		; FCB: ????????.??? on the unit
	lxi	b,FCBLEN
	call	zfill
	lda	dunit
	inr	a
	sta	tmpfcb
	lxi	h,tmpfcb+1
	mvi	b,11
sb1:	mvi	m,'?'
	inx	h
	dcr	b
	jnz	sb1
	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS

	; Skip 22 entries for each block before this one, then take 22.
	lhld	synblk
	mov	d,h
	mov	e,l
	dad	h			; * 22 = * 16 + * 4 + * 2
	push	h
	dad	h
	push	h
	dad	h
	dad	h
	pop	d
	dad	d
	pop	d
	dad	d
	shld	synskip
	xra	a
	sta	synn
	mvi	c,F_SFIRST
sb.srch: lxi	d,tmpfcb
	call	BDOS
	cpi	0FFh
	jz	sb.done
	mov	b,a			; HL -> the CP/M entry
	lhld	synskip
	mov	a,h
	ora	l
	jz	sb.take
	dcx	h
	shld	synskip
	mvi	c,F_SNEXT
	jmp	sb.srch
sb.take: mov	a,b
	rrc				; * 32
	rrc
	rrc
	ani	0E0h
	lxi	h,TBUF+1
	call	rdadap
	xchg				; DE -> CP/M name
	lda	synn			; HL -> HDOS entry
	call	synent
	mvi	b,11			; name: no attribute bits, blanks -> 0
sb2:	ldax	d
	ani	7Fh
	cpi	' '
	jnz	sb3
	xra	a
sb3:	mov	m,a
	inx	h
	inx	d
	dcr	b
	jnz	sb2
	dcx	d			; flags: SYS (t2) -> S, R/O (t1) -> W
	dcx	d
	ldax	d
	ani	80h
	mov	c,a			; SYS
	dcx	d
	ldax	d
	ani	80h
	rrc
	rrc
	ora	c			; R/O -> 20H
	inx	h			; DIR.FLG is entry + 0EH
	inx	h
	inx	h
	mov	m,a
	lxi	h,synn
	inr	m
	mov	a,m
	cpi	DIRENT
	jz	sb.full
	mvi	c,F_SNEXT
	jmp	sb.srch
sb.done: lda	synn			; past the last file
	ora	a
	jnz	sb.end
	lhld	synblk			; block 0 may be empty, no other
	mov	a,h
	ora	l
	stc
	rnz
sb.end:	lda	synn			; mark the end of the directory
	call	synent
	mvi	m,DF.CLR
	lxi	h,0			; no next block
	jmp	sb.trl
sb.full: lhld	synblk			; there may be another block
	inx	h
sb.trl:	xchg
	lhld	psec
	lxi	b,DIS.LNK
	dad	b
	mov	m,e
	inx	h
	mov	m,d
	lhld	psec
	lxi	b,DIS.ENL
	dad	b
	mvi	m,DIRELEN
	inx	h
	xchg
	lhld	synblk
	xchg
	mov	m,e			; DIS.SEC: the block number
	inx	h
	mov	m,d

	; Sizes, and the GRT: each file gets its own chain of groups.
	lda	dunit
	call	uent
	inx	h
	mov	a,m
	sta	hspg
	inx	h
	inx	h
	mov	h,m			; clear the GRT page
	mvi	l,0
	shld	syngrt
	lxi	b,256
	call	zfill
	mvi	a,2			; groups 0 and 1 are never used
	sta	syng
	xra	a
	sta	syni
sb.size: lda	syni
	lxi	h,synn
	cmp	m
	jnc	sb.free
	call	synent			; FCB for the file
	shld	synep
	lxi	h,tmpfcb2
	lxi	b,FCBLEN
	call	zfill
	lda	dunit
	inr	a
	sta	tmpfcb2
	lhld	synep
	lxi	d,tmpfcb2+1
	mvi	b,11
sb4:	mov	a,m
	ora	a
	jnz	sb5
	mvi	a,' '
sb5:	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	sb4
	lxi	d,tmpfcb2
	mvi	c,F_SIZE
	call	BDOS
	lhld	tmpfcb2+FCB.R0		; sectors = (records + 1) / 2
	inx	h
	ora	a
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	call	synchain		; HL sectors -> FGN, LGN, LSI
	lxi	h,syni
	inr	m
	jmp	sb.size

	; Free space: a chain hung on GRT[0].
sb.free: call	cpmfree			; HL = free sectors
	lda	hspg			; groups = sectors / SPG
	mov	e,a
	mvi	d,0
	mov	b,h
	mov	c,l
	call	rdu66
	lda	syng			; no more than are left
	cma
	mov	b,a			; B = 255 - next group
	mov	a,h
	ora	a
	jnz	sf1
	mov	a,l
	cmp	b
	jc	sf2
sf1:	mov	l,b
sf2:	mov	a,l
	ora	a
	rz				; none free (NC)
	mov	b,a
	lhld	syngrt			; GRT[0] = first free group
	lda	syng
	mov	m,a
	call	synlink
	ora	a
	ret

; synchain - give entry synep a chain for HL sectors.
synchain: push	h
	mov	a,h			; groups = (sectors + SPG - 1) / SPG
	ora	l
	lxi	d,1			; (an empty file still gets one)
	jz	sc.1
	lda	hspg
	dcr	a
	call	rdadap
	mov	b,h
	mov	c,l
	lda	hspg
	mov	e,a
	mvi	d,0
	call	rdu66
	xchg				; DE = groups
sc.1:	pop	h			; LSI = sectors - (groups-1) * SPG
	push	d
	dcx	d
	push	h
	lda	hspg
	call	rmu86			; HL = (groups-1) * SPG
	xchg
	pop	h
	mov	a,l
	sub	e
	mov	c,a			; C = LSI
	pop	d			; E = groups
	lda	syng			; room for them?
	add	e
	jc	sc.2
	cpi	255
	jc	sc.3
sc.2:	mvi	e,1			; no: say one group, empty
	mvi	c,0
sc.3:	mov	a,c
	sta	synlsi
	lhld	synep			; FGN, LGN, LSI
	lxi	b,DIR.FGN
	dad	b
	lda	syng
	mov	m,a
	inx	h
	add	e
	dcr	a
	mov	m,a
	inx	h
	lda	synlsi
	mov	m,a
	mov	b,e
	jmp	synlink

; synlink - chain B groups from syng in the GRT; syng moves past them.
synlink: lhld	syngrt
	lda	syng
	mov	l,a
sl1:	dcr	b
	jz	sl2
	inr	a
	mov	m,a
	mov	l,a
	jmp	sl1
sl2:	mvi	m,0			; end of the chain
	inr	a
	sta	syng
	ret

; synent - A = entry number: HL -> that entry of the block in psec.
synent:	push	d
	mov	e,a
	mvi	d,0
	mvi	a,DIRELEN
	call	rmu86
	xchg
	lhld	psec
	dad	d
	pop	d
	ret

; cpmfree - HL = free 256-byte sectors on CP/M unit dunit, from its
; allocation vector.
cpmfree: mvi	c,DRV_GET		; select the unit for a moment
	call	BDOS
	push	psw
	lda	dunit
	mov	e,a
	mvi	c,DRV_SEL
	call	BDOS
	mvi	c,DRV_DPB
	call	BDOS
	inx	h			; BSH
	inx	h
	mov	a,m
	sta	cfbsh
	inx	h
	inx	h
	inx	h			; DSM
	mov	e,m
	inx	h
	mov	d,m
	inx	d			; DE = blocks
	push	d
	mvi	c,DRV_ALLOC
	call	BDOS
	pop	d
	lxi	b,0			; BC = free blocks
cf1:	mov	a,m
	push	h
	mvi	h,8
cf2:	rlc
	jc	cf3
	inx	b
cf3:	dcx	d
	push	psw
	mov	a,d
	ora	e
	jz	cf4
	pop	psw
	dcr	h
	jnz	cf2
	pop	h
	inx	h
	jmp	cf1
cf4:	pop	psw
	pop	h
	pop	psw			; select the drive we had
	push	b
	mov	e,a
	mvi	c,DRV_SEL
	call	BDOS
	pop	h			; sectors = blocks << (BSH - 1)
	lda	cfbsh
	dcr	a
	rz
cf5:	dad	h
	dcr	a
	jnz	cf5
	ret

; zfill - zero BC bytes at HL.
zfill:	mvi	m,0
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	zfill
	ret

; isdir - Z if dnam names DIRECT.SYS.
isdir:	lxi	h,dnam+3
	lxi	d,ndirect
	mvi	c,11
	jmp	rcomp
ndirect: db	'DIRECT',0,0,'SYS'

