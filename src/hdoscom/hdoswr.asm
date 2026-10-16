; hdoswr.asm - writing HDOS disks: create, update, close, delete,
; rename (see hdosfs.asm)
;
; As on HDOS: .OPENW takes the file's first group at once and enters
; the file in the directory only at .CLOSE, replacing any old file of
; that name; .CLEAR gives its groups back. Groups come off the free
; chain that starts at GRT[0]. The GRT is kept in memory and written
; back, with the changed directory block, at each close, delete and
; rename.

DF.WP	equ	20h		; directory flag: write protected

; hcreate - .OPENW/.OPENC of dnam on HDOS unit dunit, on channel chp.
hcreate: call	hlook			; an old file must not be write
	jc	hc1			; protected, and for .OPENC must
	lda	chnoex			; not be there at all
	ora	a
	mvi	a,EC.FAP
	stc
	rnz
	call	hwpchk
	rc
hc1:	call	hstate
	lda	dunit
	mov	m,a			; HC.UNIT
	call	hunit			; HC.SPG, HC.GRT
	call	galloc			; its first group
	rc
	lhld	hst
	inx	h
	mov	m,a			; HC.FGN
	inx	h
	mov	m,a			; HC.CUR
	inx	h
	mvi	m,0			; HC.IDX
	inx	h
	mov	m,a			; HC.LGN
	inx	h
	mvi	m,0			; HC.LSI
	mvi	a,CM.HWR
	call	setmode
	ora	a
	ret

; hunit - copy unit dunit's SPG and GRT page into chp's state.
hunit:	lda	dunit
	call	uent
	inx	h
	mov	b,m			; SPG
	inx	h
	inx	h
	mov	c,m			; GRT page
	mvi	a,HC.SPG
	call	hfld
	mov	m,b
	inx	h
	mov	m,c
	ret

; hwpchk - HL -> directory entry: CY and A = EC.WPV if write
; protected. Keeps HL.
hwpchk:	push	h
	lxi	d,DIR.FLG
	dad	d
	mov	a,m
	pop	h
	ani	DF.WP
	rz
	mvi	a,EC.WPV
	stc
	ret

; hwrite - write B sectors from DE to the HDOS file on chp.
hwrite:	mov	a,b
	ora	a
	rz
	push	b
	call	hwsec
	pop	b
	rc
	inr	d
	dcr	b
	jmp	hwrite

; hwsec - write the sector at DE as the file's next sector: over an
; old one, or added at the end. Keeps DE.
hwsec:	call	hstate
	mvi	a,HC.CUR		; at the end? (no current group, or
	call	hfld			; past LSI in the last one)
	mov	a,m
	ora	a
	jz	hw.add
	mov	c,a
	mvi	a,HC.LGN
	call	hfld
	mov	a,m
	cmp	c
	jnz	hw.old
	mvi	a,HC.IDX
	call	hfld
	mov	b,m
	mvi	a,HC.LSI
	call	hfld
	mov	a,b
	cmp	m
	jnc	hw.add
hw.old:	call	hnext			; HL = the sector to write over
	jmp	hw.wr
hw.add:	mvi	a,HC.LGN		; room left in the last group?
	call	hfld
	mov	a,m
	ora	a
	jz	hw.grp			; (an empty file has none)
	mvi	a,HC.SPG
	call	hfld
	mov	b,m
	mvi	a,HC.LSI
	call	hfld
	mov	a,m
	cmp	b
	jc	hw.in
hw.grp:	push	d			; no: take a group, chain it on
	call	galloc
	pop	d
	rc
	sta	hcur
	mvi	a,HC.LGN
	call	hfld
	mov	b,m			; B = old last group
	lda	hcur
	mov	m,a			; HC.LGN = new group
	mov	a,b
	ora	a
	jnz	hw.lnk
	mvi	a,HC.FGN		; the file's first group
	call	hfld
	lda	hcur
	mov	m,a
	jmp	hw.ls
hw.lnk:	mvi	a,HC.GRT		; GRT[old last] = new group
	call	hfld
	mov	h,m
	mov	l,b
	lda	hcur
	mov	m,a
hw.ls:	mvi	a,HC.LSI
	call	hfld
	mvi	m,0
hw.in:	mvi	a,HC.LGN		; sector = LGN * SPG + LSI
	call	hfld
	mov	a,m
	sta	hcur
	mvi	a,HC.CUR		; and the file is positioned after it
	call	hfld
	lda	hcur
	mov	m,a
	mvi	a,HC.LSI
	call	hfld
	mov	a,m
	sta	hidx
	inr	m			; LSI + 1
	mov	b,m
	mvi	a,HC.IDX
	call	hfld
	mov	m,b
	mvi	a,HC.SPG
	call	hfld
	push	d
	lda	hcur
	mov	e,a
	mvi	d,0
	mov	a,m
	call	rmu86
	pop	d
	lda	hidx
	call	rdadap
hw.wr:	push	d
	push	h
	mvi	a,HC.UNIT
	call	hfld
	mov	a,m
	pop	h
	call	wrsec
	pop	d
	ret

; hclose - finish a write or update on chp: enter the file in the
; directory and write the GRT.
hclose:	call	hstate
	lhld	chp			; its name and unit
	lxi	d,CH.DNAM
	dad	d
	lxi	d,dnam
	mvi	b,14
	call	move
	mvi	a,HC.UNIT
	call	hfld
	mov	a,m
	sta	dunit
	call	hlook			; old entry?
	shld	hent
	mvi	a,0
	ral
	mov	b,a			; B = 1 if there is none
	lhld	chp
	mov	a,m
	cpi	CM.HUP
	jz	hcl.u
	dcr	b
	jz	hcl.n
	lhld	hent			; a new file replaces the old
	call	hdel1
	rc
hcl.n:	call	dirslot			; a free entry
	rc
	shld	hent
	lxi	b,DIRELEN
	call	zfill
	lhld	hent			; name and type
	xchg
	lxi	h,dnam+3
	mvi	b,11
	call	move
	lhld	hent			; cluster factor, as HDOS writes
	lxi	d,DIR.CLU
	dad	d
	mvi	m,3
	lhld	hent
	lxi	d,DIR.FGN
	dad	d
	mvi	a,HC.FGN
	call	hcopy
	lhld	hent
	call	hsetend			; LGN, LSI
	lhld	hent			; created today
	lxi	d,DIR.CRD
	dad	d
	xchg
	lhld	HDATE
	xchg
	mov	m,e
	inx	h
	mov	m,d
	jmp	hcl.d
hcl.u:	dcr	b			; update: the entry must be there
	mvi	a,EC.FNF
	stc
	rz
	lhld	hent
	call	hsetend
hcl.d:	lhld	hent			; altered today
	lxi	d,DIR.ALD
	dad	d
	xchg
	lhld	HDATE
	xchg
	mov	m,e
	inx	h
	mov	m,d
	call	wrdir
	rc
	jmp	wrgrt

; hsetend - HL -> directory entry: set its LGN and LSI from chp.
hsetend: lxi	d,DIR.LGN
	dad	d
	mvi	a,HC.LGN
	call	hcopy
	inx	h
	mvi	a,HC.LSI
; hcopy - (HL) = state field A. Keeps HL.
hcopy:	push	h
	call	hfld
	mov	a,m
	pop	h
	mov	m,a
	ret

; hclear - .CLEAR of a write on chp: give its groups back.
hclear:	call	hstate
	mvi	a,HC.UNIT
	call	hfld
	mov	a,m
	sta	dunit
	mvi	a,HC.GRT
	call	hfld
	mov	h,m
	push	h
	mvi	a,HC.FGN
	call	hfld
	mov	a,m
	pop	h
	jmp	gfree			; the GRT on disk never had them

; hdel1 - HL -> directory entry in psec: free its chain, empty it and
; write the block.
hdel1:	push	h
	lxi	d,DIR.FGN
	dad	d
	mov	a,m
	push	psw
	lda	dunit
	call	uent
	lxi	d,UNT.GRT+1
	dad	d
	mov	h,m
	pop	psw
	call	gfree
	pop	h
	mvi	m,DF.EMP

; wrdir - write the directory block in psec back.
wrdir:	lhld	psec
	xchg
	lhld	hlblk
	lda	dunit
	call	wrsec
	rc
	lhld	psec
	inr	h
	xchg
	lhld	hlblk
	inx	h
	lda	dunit
	jmp	wrsec

; wrgrt - write unit dunit's GRT back.
wrgrt:	lda	dunit
	call	uent
	lxi	d,UNT.GRT
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	inx	h
	mov	a,m			; UNT.GTS
	inx	h
	mov	h,m
	mov	l,a
	lda	dunit
	jmp	wrsec

DIR.CLU	equ	0Dh		; cluster factor
DIR.CRD	equ	13h		; created (coded date)
DIR.ALD	equ	15h		; altered

hent:	dw	0			; directory entry being made
hrold:	ds	11
hrnew:	ds	11
