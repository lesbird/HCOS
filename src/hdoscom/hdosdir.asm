; hdosdir.asm - HDOS GRT and directory changes: allocate and free
; groups, free entries, delete, rename
; (see hdoswr.asm)

; galloc - take a group off unit chp's free chain: A = its number.
; CY and A = EC.EOM if the disk is full. Keeps BC, DE.
galloc:	mvi	a,HC.GRT
	call	hfld
	mov	h,m
	mvi	l,0
	mov	a,m			; GRT[0] = first free group
	ora	a
	jz	ga.full
	mov	l,a
	push	psw
	mov	a,m			; GRT[0] = the one after it
	mvi	m,0			; and it ends a chain now
	mvi	l,0
	mov	m,a
	pop	psw
	ret
ga.full: mvi	a,EC.EOM
	stc
	ret

; gfree - give the chain starting at group A back to the free chain
; of the GRT in page H.
gfree:	ora	a
	rz
	mov	l,a
	mov	b,a			; B = this group
	mov	c,m			; C = the next
	mvi	l,0
	mov	a,m
	mov	l,b
	mov	m,a			; GRT[this] = old head
	mvi	l,0
	mov	m,b			; head = this
	mov	a,c
	jmp	gfree

; dirslot - find a free directory entry on unit dunit. Exit HL -> it
; in psec (block hlblk); CY and A = EC.DIF if the directory is full.
dirslot: lxi	h,0FFFFh
	shld	synblk
	lda	dunit
	call	uent
	lxi	d,UNT.DIS
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
ds.blk:	mov	a,h
	ora	l
	jz	ds.full
	call	rdblk
	rc
	lhld	psec
	mvi	b,DIRENT
ds.ent:	mov	a,m
	cpi	DF.EMP
	rz				; (Z, and NC from the compare)
	cpi	DF.CLR
	jz	ds.clr
	ora	a
	jz	ds.next
	lxi	d,DIRELEN
	dad	d
	dcr	b
	jnz	ds.ent
ds.next: lhld	psec
	lxi	d,DIS.LNK
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	jmp	ds.blk
ds.clr:	dcr	b			; the rest is empty: the next entry
	rz				; (if in this block) says so now
	push	h
	lxi	d,DIRELEN
	dad	d
	mvi	m,DF.CLR
	pop	h
	ora	a
	ret
ds.full: mvi	a,EC.DIF
	stc
	ret

; hdelete - .DELET of dnam on HDOS unit dunit.
hdelete: call	hlook
	rc
	call	hwpchk
	rc
	call	hdel1
	rc
	jmp	wrgrt

; hrename - .RENAM of dnam on HDOS unit dunit to the name at HL.
hrename: push	h
	lxi	h,dnam+3		; keep the old name
	lxi	d,hrold
	mvi	b,11
	call	move
	pop	h
	lxi	b,zdef			; new name: no defaults, and any
	call	decode			; device in it is ignored
	rc
; hren2 - the same, with the new name already in dnam (and the old in
; hrold).
hren2:	lda	dnam+3
	ora	a
	mvi	a,EC.IFN
	stc
	rz
	lxi	h,dnam+3
	lxi	d,hrnew
	mvi	b,11
	call	move
	call	hlook			; refuse to make a duplicate
	mvi	a,EC.FAP
	cmc
	rc
	lxi	h,hrold
	lxi	d,dnam+3
	mvi	b,11
	call	move
	call	hlook
	rc
	call	hwpchk
	rc
	xchg				; new name into the entry
	lxi	h,hrnew
	mvi	b,11
	call	move
	jmp	wrdir
