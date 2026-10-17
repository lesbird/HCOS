; kfs.asm - the CP/M file system of the HCOS BDOS (see bdos.asm)
;
; Disks are described by the BIOS's DPH and DPB. A disk is logged in
; the first time it is selected after a reset: its allocation vector
; is built from the directory and its directory checksums are taken.
; A checksum that changes later means the disk was changed, and the
; disk becomes R/O, as in CP/M 2.2.

; ---- Disk functions ----

; f13 - reset the disk system: nothing logged in or R/O, DMA at 80H,
; drive A selected. Also clears the console state: the CCP calls this
; first thing after every boot.
f13:	lxi	h,0
	shld	dlog
	shld	rodsk
	shld	kbchar			; kbchar, column
	shld	compcol			; compcol, listcp
	lxi	h,TBUF
	shld	dma
	xra	a
	sta	curdsk
	jmp	seldrv

; f14 - select drive E.
f14:	mov	a,c
	sta	curdsk
	jmp	seldrv

; f24 - login vector; f29 - R/O vector; f27 - allocation vector
; address; f31 - DPB address.
f24:	lhld	dlog
	jmp	setretw
f29:	lhld	rodsk
	jmp	setretw
f27:	lhld	alvp
	jmp	f31a
f31:	lhld	dpbp
f31a:	shld	aret			; offered to the kernel extension:
	lxi	d,aret			; for an HDOS disk it puts its own
	lda	fnum			; in aret
	mov	c,a
	lda	curdsk
	jmp	KXVEC
setretw: shld	aret
	ret

f25:	lda	curdsk
	jmp	setret

; f26 - set DMA address
f26:	xchg
	shld	dma
	ret

; f28 - make the current disk R/O
f28:	lda	curdsk
	jmp	setro

; f32 - get (E = FFH) or set the user number
f32:	mov	a,c
	inr	a
	lda	curusr
	jz	setret
	mov	a,c
	ani	1Fh
	sta	curusr
	ret

; f37 - reset the drives in vector DE
f37:	mov	a,e
	cma
	mov	e,a
	mov	a,d
	cma
	mov	d,a
	lhld	dlog
	call	andhd
	shld	dlog
	lhld	rodsk
	call	andhd
	shld	rodsk
	ret

andhd:	mov	a,l
	ana	e
	mov	l,a
	mov	a,h
	ana	d
	mov	h,a
	ret
orhd:	mov	a,l
	ora	e
	mov	l,a
	mov	a,h
	ora	d
	mov	h,a
	ret

; ---- Selecting and logging in ----

; seldrv - select drive A: its DPH from the BIOS, a copy of its DPB.
; Log it in if it isn't. Select error if there is no such drive.
seldrv:	sta	seldsk
	call	drvbit
	xchg
	lhld	dlog
	call	andhd
	mov	a,h
	ora	l
	jz	sd0
	mvi	a,1
sd0:	sta	logged			; 0: log it in
	mov	e,a			; BIOS: 0 = first select
	lda	seldsk
	mov	c,a
	call	B.SELDSK
	mov	a,h
	ora	l
	jz	selerr
	mov	e,m			; DPH: XLT, 3 words, dirbuf, DPB,
	inx	h			; CSV, ALV
	mov	d,m
	xchg
	shld	xltp
	lxi	h,7
	dad	d
	lxi	d,dirbuf
	mvi	c,8
	call	move
	lhld	dpbp
	lxi	d,dpb
	mvi	c,15
	call	move
	lda	logged
	ora	a
	rnz
	lda	KXVEC			; no HDOS extension (the hook is
	cpi	37h			; still STC): is it an HDOS disk?
	cz	hdchk
	; Log it in.
	lda	seldsk
	call	drvbit
	xchg
	lhld	dlog
	call	orhd
	shld	dlog
	lhld	dsm			; clear the vector: DSM/8 + 1 bytes
	call	shr3
	inx	h
	mov	b,h
	mov	c,l
	lhld	alvp
li1:	mvi	m,0
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	li1
	lhld	al0			; the directory's blocks
	xchg
	lhld	alvp
	mov	m,e
	inx	h
	mov	m,d
	call	dirrst			; and every file's
li2:	call	dirnext
	jc	li3
	mov	a,m
	cpi	20h			; users 0-31 only (E5H is empty)
	jnc	li2
	lxi	b,curusr		; a name starting with "$" in this
	ldax	b			; user area: return FFH. (The CCP
	cmp	m			; runs $$$.SUB when f13 does.)
	jnz	li2a
	inx	h
	mov	a,m
	dcx	h
	cpi	'$'
	jnz	li2a
	mvi	a,0FFh
	sta	aret
li2a:	mvi	c,1
	call	mapalv
	jmp	li2
li3:	mvi	a,1			; checksums are taken now
	sta	logged
	ret

; hdchk - is the drive being logged in an HDOS disk? Its label is
; physical sector 9 of track 0, which BIOS record 14 starts (the BIOS
; skews host sectors, and logical sector 7 is physical 9). If the label
; looks right, set KXNEED, so the shell loads the HDOS extension at the
; next warm boot, and give a select error.
hdchk:	lxi	b,0
	call	B.SETTRK
	lxi	b,14
	call	B.SETSEC
	lhld	dirbuf
	push	h
	mov	b,h
	mov	c,l
	call	B.SETDMA
	call	B.READ
	pop	h
	ora	a
	rnz				; unreadable: not HDOS
	lxi	d,0Eh			; 256-byte sectors
	dad	d
	mov	a,m
	ora	a
	rnz
	inx	h
	mov	a,m
	cpi	1
	rnz
	lxi	d,4Fh-0Fh		; 10 a track
	dad	d
	mov	a,m
	cpi	10
	rnz
	mvi	a,1
	sta	KXNEED
	pop	h
	jmp	selerr

; drvbit - HL = 1 << A (A = drive 0-15).
drvbit:	lxi	h,1
	ani	0Fh
db1:	rz
	dad	h
	dcr	a
	jmp	db1

; mapalv - mark the blocks of the directory entry at HL used (C = 1)
; or free (C = 0). Block numbers over DSM are skipped.
mapalv:	mov	a,c
	sta	mamode
	lxi	d,F.MAP
	dad	d
	call	mapn
ma1:	push	b
	call	getmap
	mov	a,d
	ora	e
	jz	ma2
	push	h
	lhld	dsm			; past the end of the disk: a
	call	cmpde			; directory that isn't CP/M's (an
	jc	ma3			; HDOS disk); the bit would land in
	xchg				; whatever follows the vector
	lda	mamode
	mov	c,a
	call	setalv
ma3:	pop	h
ma2:	pop	b
	dcr	b
	jnz	ma1
	ret

; mapn - B = block numbers in a map: 16, or 8 when they are 16-bit.
mapn:	lda	dsm+1
	ora	a
	mvi	b,16
	rz
	mvi	b,8
	ret

; getmap - DE = the block number at HL (one or two bytes); HL past it.
getmap:	mov	e,m
	inx	h
	mvi	d,0
	lda	dsm+1
	ora	a
	rz
	mov	d,m
	inx	h
	ret

; shr3 - HL = HL / 8; shrb - HL >> B.
shr3:	mvi	b,3
shrb:	ora	a
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	dcr	b
	jnz	shrb
	ret

; alvadr - block HL: HL -> its byte in the vector, A = its bit.
; Keeps C.
alvadr:	mov	a,l
	ani	7
	mov	b,a
	mvi	a,80h
aa1:	dcr	b
	jm	aa2
	rrc
	jmp	aa1
aa2:	push	psw
	call	shr3
	xchg
	lhld	alvp
	dad	d
	pop	psw
	ret

; setalv - mark block HL used (C = 1) or free (C = 0).
setalv:	call	alvadr
	mov	b,a
	cma
	ana	m
	dcr	c
	jnz	sa1
	ora	b
sa1:	mov	m,a
	ret

; getfree - DE = a free block after block HL (wrapping round), marked
; used; DE = 0 if the disk is full.
getfree: lhld	dsm
	inx	h
	shld	gfcnt			; blocks to look at
	xchg
gf1:	inx	d			; the next one
	lhld	dsm
	call	cmpde			; DSM < DE: wrap to 0
	jnc	gf2
	lxi	d,0
gf2:	push	d
	xchg
	call	alvadr
	ana	m
	pop	d
	jz	gf3			; free
	lhld	gfcnt
	dcx	h
	shld	gfcnt
	mov	a,h
	ora	l
	jnz	gf1
	lxi	d,0
	ret
gf3:	push	d
	xchg
	mvi	c,1
	call	setalv
	pop	d
	ret

; ---- Records ----

; seek - set the BIOS to logical record HL of the selected disk.
seek:	lxi	b,0			; BC = track
	xchg
	lhld	spt
	xchg				; DE = SPT
sk1:	call	cmpde			; while record >= SPT
	jc	sk2
	mov	a,l
	sub	e
	mov	l,a
	mov	a,h
	sbb	d
	mov	h,a
	inx	b
	jmp	sk1
sk2:	push	h
	lhld	off
	dad	b
	mov	b,h
	mov	c,l
	call	B.SETTRK
	pop	b			; sector
	lhld	xltp
	xchg
	call	B.SECTRAN
	mov	b,h
	mov	c,l
	jmp	B.SETSEC

; dskrd - read record HL into BC. dskwr - write it from BC, type A.
dskrd:	push	b
	call	seek
	pop	b
	call	B.SETDMA
	call	B.READ
	jmp	rwchk
dskwr:	sta	wtype
	push	b
	call	seek
	pop	b
	call	B.SETDMA
	lda	wtype
	mov	c,a
	call	B.WRITE
rwchk:	ora	a
	rz
	jmp	perr

; ---- The directory ----

; dirrst - start a directory scan. dirnext - HL -> the next entry
; (reading its record when needed), or CY past the last.
dirrst:	lxi	h,0FFFFh
	shld	dcnt
	ret
dirnext: lhld	dcnt
	inx	h
	shld	dcnt
	xchg
	lhld	drm
	call	cmpde			; DRM < dcnt: past the end
	rc
	mov	a,e
	ani	3
	cz	dirrd
dirent:	lda	dcnt			; HL -> entry dcnt in dirbuf
	ani	3
	rrc
	rrc
	rrc
	lhld	dirbuf
	call	dada
	ora	a
	ret

; dirrec - HL = the directory record dcnt is in.
dirrec:	lhld	dcnt
	mvi	b,2
	jmp	shrb

; dirrd - read dcnt's record into dirbuf; check its checksum (or take
; it, logging in).
dirrd:	call	dirrec
	push	h
	lhld	dirbuf
	mov	b,h
	mov	c,l
	pop	h
	push	h
	call	dskrd
	pop	h
	lda	logged
	jmp	ckrec

; dirwr - write dcnt's record back, and take its new checksum.
dirwr:	call	ckro
	call	dirrec
	push	h
	lhld	dirbuf
	mov	b,h
	mov	c,l
	pop	h
	push	h
	mvi	a,1			; directory write
	call	dskwr
	pop	h
	xra	a
; ckrec - for directory record HL: take its checksum (A = 0) or
; check it (A <> 0; a change makes the disk R/O).
ckrec:	sta	ckmode
	xchg
	lhld	cks
	call	cmpde			; records under CKS are checked
	rc
	rz
	lhld	csvp
	dad	d
	push	h
	lhld	dirbuf
	mvi	b,128
	xra	a
ck1:	add	m
	inx	h
	dcr	b
	jnz	ck1
	pop	h
	mov	b,a
	lda	ckmode
	ora	a
	jz	ck2
	mov	a,b
	cmp	m
	rz
	lda	seldsk
	jmp	setro
ck2:	mov	m,b
	ret

; setro - make drive A R/O.
setro:	call	drvbit
	xchg
	lhld	rodsk
	call	orhd
	shld	rodsk
	ret

; ckro - "R/O" error if the selected disk is R/O.
ckro:	lda	seldsk
	call	drvbit
	xchg
	lhld	rodsk
	call	andhd
	mov	a,h
	ora	l
	rz
	jmp	roderr

; ckrof - "File R/O" if the directory entry or FCB at HL is R/O.
; Keeps HL.
ckrof:	push	h
	lxi	d,F.T1
	dad	d
	mov	a,m
	pop	h
	ral
	rnc
	jmp	roferr

; ---- Searching ----

; search - find the first entry matching the first C bytes of the FCB
; at info (C = 0: every entry). HL -> it, or CY.
search:	mov	a,c
	sta	searchl
	lhld	info
	shld	searcha
	call	dirrst
; searchn - the next match.
searchn: call	dirnext
	rc
	lda	searchl
	ora	a
	rz				; every entry matches
	mov	c,a
	push	h
	xchg				; DE -> entry
	lhld	searcha			; HL -> pattern
	mvi	b,0			; byte number
sn1:	mov	a,b
	cmp	c
	jz	sn.ok
	mov	a,m
	cpi	'?'
	jz	sn.nx
	mov	a,b
	cpi	F.EX+1			; S1 isn't compared
	jz	sn.nx
	cpi	F.EX
	ldax	d
	jz	sn.ex
	xra	m
	ani	7Fh			; attribute bits don't count
	jnz	sn.no
sn.nx:	inx	h
	inx	d
	inr	b
	jmp	sn1
sn.ex:	xra	m			; extent: the bits under EXM don't
	push	b			; count
	mov	c,a
	lda	exm
	cma
	ani	1Fh
	ana	c
	pop	b
	jz	sn.nx
sn.no:	pop	h
	jmp	searchn
sn.ok:	pop	h
	ora	a
	ret

; f17 / f18 - search first / next: the directory record goes to the
; DMA address; returns the entry's number in it (0-3), or FFH.
f17:	lhld	info			; (for f18, even if the kernel
	shld	srinfo			; extension does the search)
	mov	a,m
	cpi	'?'			; "?" drive: every entry
	mvi	c,0
	jz	f17a
	lxi	d,F.EX			; module 0 unless any extent
	dad	d
	mov	a,m
	cpi	'?'
	cnz	clrs2
	call	reselect
	mvi	c,15
f17a:	call	search
	jmp	f18a
f18:	lhld	srinfo			; the same FCB, drive and user
	shld	info
	mov	a,m
	cpi	'?'
	cnz	reselect
	call	searchn
f18a:	jc	retff
	lhld	info
	shld	srinfo
	lhld	dirbuf
	xchg
	lhld	dma
	xchg
	mvi	c,128
	call	move
dircode: lda	dcnt
	ani	3
	jmp	setret

; reselect - select the FCB's drive for this call, and put the user
; number in its drive byte for matching. goback undoes both.
reselect:
	lhld	info
	mov	a,m
	sta	fcbdsk
	ani	1Fh
	dcr	a
	jp	rs1
	lda	curdsk			; 0: the current drive
rs1:	push	psw			; the kernel extension's? (HDOS
	lda	fnum			; disks)
	mov	c,a
	lhld	info
	xchg
	lhld	dma
	pop	psw
	push	psw
	call	KXVEC
	jc	rsx
	sta	aret			; done there
	jmp	retmon
rsx:	pop	psw
	push	psw
	lda	curdsk
	sta	olddsk
	mvi	a,1
	sta	resel
	pop	psw
	call	seldrv
	lhld	info
	lda	curusr
	mov	m,a
	ret

; fcbf - HL -> field A of the FCB at info. Keeps DE... uses A.
fcbf:	lhld	info
	jmp	dada

; clrs2 - clear the FCB's S2 (module) byte.
clrs2:	mvi	a,F.S2
	call	fcbf
	mvi	m,0
	ret

; setfwf - mark the FCB "not written since open" (S2 bit 7).
setfwf:	mvi	a,F.S2
	call	fcbf
	mov	a,m
	ori	FWF
	mov	m,a
	ret

; ---- Open, close, make ----

f15:	call	clrs2
	call	reselect
; open - find the FCB's extent and copy its entry into the FCB. The
; record count is for the logical extent asked for: the entry's own
; if it's the entry's last, 128 if before it, 0 if after.
open:	mvi	c,15
	call	search
	jc	retff
	shld	entp
	mvi	a,F.EX
	call	fcbf
	mov	a,m
	sta	reqex
	lhld	info			; entry bytes 1-31 to the FCB
	inx	h
	xchg
	lhld	entp
	inx	h
	mvi	c,31
	call	move
	lhld	entp
	lxi	d,F.EX
	dad	d
	mov	c,m			; entry's extent
	inx	h
	inx	h
	inx	h
	mov	b,m			; entry's record count
	mvi	a,F.EX
	call	fcbf
	lda	reqex
	mov	m,a
	cmp	c
	mov	a,b
	jz	op1
	mvi	a,0
	jnc	op1
	mvi	a,128
op1:	inx	h
	inx	h
	inx	h
	mov	m,a
	call	setfwf
	jmp	dircode

; f16 - close
f16:	call	reselect
close:	mvi	a,F.S2			; not written since open: done,
	call	fcbf			; and 0 (as DRI's; not the code of
	mov	a,m			; the last directory search)
	ani	FWF
	mvi	a,0
	jnz	setret
	call	ckro
	mvi	c,15
	call	search
	jc	retff
	shld	entp
	; Merge the maps: each byte from whichever has it.
	lxi	d,F.MAP
	dad	d
	push	h
	mvi	a,F.MAP
	call	fcbf
	pop	d
	mvi	c,16
cl1:	ldax	d			; DE -> entry, HL -> FCB
	ora	a
	jnz	cl2
	mov	a,m
	stax	d
	jmp	cl3
cl2:	mov	b,a
	mov	a,m
	ora	a
	jz	cl2a
	cmp	b
	jnz	retff			; different blocks: can't close
cl2a:	mov	m,b
cl3:	inx	d
	inx	h
	dcr	c
	jnz	cl1
	; Extent and count: the FCB's, unless the entry's extent is past
	; it. (The CCP shortens $$$.SUB by closing it with a smaller
	; count.)
	mvi	a,F.EX
	call	fcbf
	mov	b,m
	inx	h
	inx	h
	inx	h
	mov	c,m
	lhld	entp
	lxi	d,F.EX
	dad	d
	mov	a,m
	cmp	b
	jz	cl4
	jnc	cl5
cl4:	mov	m,b
	inx	h
	inx	h
	inx	h
	mov	m,c
cl5:	call	dirwr
	call	setfwf
	jmp	dircode

; f22 - make
f22:	call	clrs2
	call	reselect
make:	call	ckro
	lhld	info			; find an empty entry
	mov	a,m
	push	psw
	mvi	m,EMPTY
	mvi	c,1
	call	search
	pop	b
	xchg				; (DE = the empty entry)
	lhld	info
	mov	m,b
	jc	retff			; directory full
	xchg
	shld	entp
	mvi	a,F.RC			; FCB: no records, no blocks
	call	fcbf
	mvi	b,17
mk1:	mvi	m,0
	inx	h
	dcr	b
	jnz	mk1
	mvi	a,F.S2
	call	fcbf
	mov	a,m
	ani	7Fh
	mov	m,a
	lhld	entp			; FCB 0-31 to the entry
	xchg
	lhld	info
	mvi	c,32
	call	move
	call	dirwr
	call	setfwf
	jmp	dircode

; ---- Delete, rename, attributes ----

; f19 - delete every extent of every matching file
f19:	call	reselect
	call	ckro
	mvi	c,12
	call	search
	jc	retff
de1:	call	ckrof
	mvi	m,EMPTY
	mvi	c,0
	call	mapalv
	call	dirwr
	call	searchn
	jnc	de1
	xra	a
	jmp	setret

; f23 - rename every extent to the name at FCB+16
f23:	call	reselect
	call	ckro
	mvi	c,12
	call	search
	jc	retff
rn1:	call	ckrof
	inx	h
	xchg
	mvi	a,17
	call	fcbf
	mvi	c,11
	call	move
	call	dirwr
	call	searchn
	jnc	rn1
	xra	a
	jmp	setret

; f30 - set attributes: copy name and type bits from the FCB
f30:	call	reselect
	mvi	c,12
	call	search
	jc	retff
at1:	inx	h
	xchg
	mvi	a,1
	call	fcbf
	mvi	c,11
	call	move
	call	dirwr
	call	searchn
	jnc	at1
	xra	a
	jmp	setret

; ---- Reading and writing ----

; f20 / f21 - read / write sequential
f20:	call	reselect
	mvi	a,1
	sta	seqio
	jmp	diskrd
f21:	call	reselect
	mvi	a,1
	sta	seqio
	xra	a
	sta	zfill
	jmp	diskwr

; f33 / f34 / f40 - read / write / write with zero fill, random
f33:	call	reselect
	xra	a
	sta	seqio
	call	rseek
	jc	setret
	jmp	diskrd
f40:	mvi	a,1
	jmp	f34a
f34:	xra	a
f34a:	sta	zfill
	call	reselect
	xra	a
	sta	seqio
	inr	a
	call	rseek
	jc	setret
	jmp	diskwr

; diskrd - read the FCB's current record to the DMA address.
diskrd:	mvi	a,F.CR
	call	fcbf
	mov	a,m
	cpi	128
	jc	dr1
	xra	a			; past this extent: the next
	call	nextext
	jc	ret1
dr1:	mvi	a,F.CR			; past the record count: end
	call	fcbf
	mov	b,m
	mvi	a,F.RC
	call	fcbf
	mov	a,b
	cmp	m
	jnc	ret1
	call	recblk			; its block; none: end
	jz	ret1
	call	absrec
	lhld	dma
	mov	b,h
	mov	c,l
	lhld	absr
	call	dskrd
	call	advcr
	xra	a
	jmp	setret

; diskwr - write the FCB's current record from the DMA address.
diskwr:	call	ckro
	lhld	info
	call	ckrof
	mvi	a,F.CR
	call	fcbf
	mov	a,m
	cpi	128
	jc	dw1
	mvi	a,1			; past this extent: the next
	call	nextext
	jc	ret1			; (no directory room)
dw1:	call	recblk
	mvi	a,0			; write type: normal
	jnz	dw3
	; No block yet: take one near the one before it.
	push	h
	lxi	h,0
	mov	a,b			; map index 0: no hint
	ora	a
	jz	dw2
	pop	h
	push	h
	dcx	h
	lda	dsm+1
	ora	a
	jz	dw1a
	dcx	h
dw1a:	call	getmap
	xchg
dw2:	call	getfree
	pop	h
	mov	a,d
	ora	e
	mvi	a,2
	jz	setret			; disk full
	mov	m,e			; into the map
	lda	dsm+1
	ora	a
	jz	dw2a
	inx	h
	mov	m,d
dw2a:	xchg
	shld	blk
	lda	zfill			; zero the whole block first?
	ora	a
	cnz	zblock
	mvi	a,2			; first write to a new block
dw3:	push	psw
	call	absrec
	lda	vrec
	lxi	h,blm
	ana	m
	pop	b
	mov	a,b
	jz	dw4
	xra	a			; not its first record: normal
dw4:	push	psw
	lhld	dma
	mov	b,h
	mov	c,l
	lhld	absr
	pop	psw
	call	dskwr
	mvi	a,F.CR			; record count = max(count, cr+1)
	call	fcbf
	mov	a,m
	inr	a
	mov	b,a
	mvi	a,F.RC
	call	fcbf
	mov	a,m
	cmp	b
	jnc	dw5
	mov	m,b
dw5:	mvi	a,F.S2			; written now
	call	fcbf
	mov	a,m
	ani	7Fh
	mov	m,a
	call	advcr
	xra	a
	jmp	setret

; zblock - write zeros to every record of block blk (dirbuf as the
; zeros).
zblock:	lhld	dirbuf
	mvi	b,128
zb1:	mvi	m,0
	inx	h
	dcr	b
	jnz	zb1
	lda	blm
	inr	a
	sta	zcnt
	lhld	blk
	lda	bsh
	mov	b,a
zb2:	dad	h
	dcr	b
	jnz	zb2
zb3:	push	h
	lhld	dirbuf
	mov	b,h
	mov	c,l
	pop	h
	push	h
	mvi	a,2
	call	dskwr
	pop	h
	inx	h
	lda	zcnt
	dcr	a
	sta	zcnt
	jnz	zb3
	ret

; advcr - sequential I/O: on to the next record.
advcr:	lda	seqio
	ora	a
	rz
	mvi	a,F.CR
	call	fcbf
	inr	m
	ret

; recblk - the FCB's current record: vrec = record in its directory
; entry, HL -> its map slot, B = slot number, DE = blk = its block;
; Z if it has none.
recblk:	mvi	a,F.EX
	call	fcbf
	lda	exm
	ana	m			; logical extent in the entry
	rrc				; * 128
	mov	d,a
	ani	80h
	mov	e,a
	mov	a,d
	ani	7Fh
	mov	d,a
	mvi	a,F.CR
	call	fcbf
	mov	a,m
	ora	e
	mov	e,a
	xchg
	shld	vrec
	lda	bsh			; slot = vrec >> BSH
	mov	b,a
	call	shrb
	mov	b,l
	mov	a,l
	lda	dsm+1
	ora	a
	mov	a,l
	jz	rb1
	add	a			; 16-bit numbers: 2 bytes each
rb1:	adi	F.MAP
	call	fcbf
	push	h
	call	getmap
	pop	h
	xchg
	shld	blk
	xchg
	mov	a,d
	ora	e
	ret

; absrec - absr = blk << BSH + (vrec AND BLM): the logical record.
absrec:	lhld	blk
	lda	bsh
	mov	b,a
ar1:	dad	h
	dcr	b
	jnz	ar1
	lda	vrec
	lxi	d,blm
	xchg
	ana	m
	xchg
	call	dada
	shld	absr
	ret

; nextext - on to the FCB's next extent (A = 0 reading, 1 writing):
; close this one if written, open the next, make it if writing. CY if
; there is none (reading) or no room for it (writing).
nextext: sta	wrflag
	call	closex
	rc
	mvi	a,F.EX
	call	fcbf
	mov	a,m
	inr	a
	ani	1Fh
	mov	m,a
	jnz	ne1
	inx	h			; into the next module
	inx	h
	mov	a,m
	inr	a
	ani	3Fh
	mov	m,a
ne1:	mvi	a,F.CR
	call	fcbf
	mvi	m,0
; openx - open the FCB's extent; make it if writing. CY if neither.
openx:	call	open
	lda	aret
	adi	1
	rnc				; opened
	lda	wrflag
	ora	a
	stc
	rz
	call	make
	lda	aret
	adi	1			; CY if FFH
	ret

; closex - close the FCB if written. CY if it couldn't be.
closex:	call	close
	lda	aret
	adi	1
	ret

; rseek - set the FCB to its random record (A = 0 reading, 1
; writing). CY and A = error: 6 past the end, 3 can't close, 4 no
; such extent (reading), 5 no directory room (writing).
rseek:	sta	wrflag
	mvi	a,F.R0
	call	fcbf
	mov	e,m
	inx	h
	mov	d,m
	inx	h
	mov	a,m
	ora	a
	mvi	a,6
	stc
	rnz
	mov	a,e			; record in the extent
	ani	7Fh
	sta	rcr
	mov	a,e			; extent = record >> 7, 5 bits
	ral
	mov	a,d
	ral
	ani	1Fh
	sta	rex
	mov	a,d			; module = record >> 12
	rrc
	rrc
	rrc
	rrc
	ani	0Fh
	sta	rs2
	mvi	a,F.EX			; the FCB's extent already?
	call	fcbf
	lda	rex
	cmp	m
	jnz	rsk1
	inx	h
	inx	h
	mov	a,m
	ani	3Fh
	lxi	h,rs2
	cmp	m
	jz	rsk2
rsk1:	call	closex
	mvi	a,3
	rc
	mvi	a,F.EX
	call	fcbf
	lda	rex
	mov	m,a
	inx	h
	inx	h
	lda	rs2			; (not written: if it doesn't open,
	ori	FWF			; there is nothing to close)
	mov	m,a
	call	openx
	jnc	rsk2
	lda	wrflag
	ora	a
	mvi	a,4
	stc
	rz
	mvi	a,5
	stc
	ret
rsk2:	mvi	a,F.CR
	call	fcbf
	lda	rcr
	mov	m,a
	xra	a
	ret

; f36 - set random record from the FCB's position.
f36:	mvi	a,F.CR
	call	fcbf
	mov	c,m
	mvi	a,F.EX
	call	fcbf
	call	recnum
	jmp	putr

; f35 - file size: one past the last record of any extent.
f35:	call	reselect
	lxi	h,0
	shld	fsize
	xra	a
	sta	fsize+2
	mvi	c,12
	call	search
fs1:	jc	fs3
	lxi	d,F.RC
	dad	d
	mov	c,m			; records in the entry's last extent
	lxi	d,F.EX-F.RC
	dad	d
	call	recnum			; AHL = its size
	sta	fshi			; bigger than fsize?
	lda	fsize+2
	mov	b,a
	lda	fshi
	cmp	b
	jc	fs2
	jnz	fsnew
	xchg
	lhld	fsize
	call	cmpde
	xchg
	jnc	fs2
fsnew:	shld	fsize
	lda	fshi
	sta	fsize+2
fs2:	call	searchn
	jmp	fs1
fs3:	lhld	fsize
	lda	fsize+2
; putr - store AHL as the FCB's random record.
putr:	push	psw
	push	h
	mvi	a,F.R0
	call	fcbf
	pop	d
	mov	m,e
	inx	h
	mov	m,d
	inx	h
	pop	psw
	mov	m,a
	ret

; recnum - AHL = record number for extent (HL) = EX, (HL+2) = S2 and
; record C: (S2 * 32 + EX) * 128 + C.
recnum:	mov	e,m			; EX
	inx	h
	inx	h
	mov	a,m			; S2
	ani	3Fh
	mov	l,a			; HL = S2 * 32 + EX
	mvi	h,0
	dad	h
	dad	h
	dad	h
	dad	h
	dad	h
	mov	a,e
	ani	1Fh
	ora	l
	mov	l,a
	; * 128 = * 256 / 2: A:H:L = 0:H:L:0 >> 1
	mov	a,h
	mov	h,l
	mvi	l,0
	ora	a
	rar
	push	psw
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	ora	c			; + C (< 128)
	mov	l,a
	pop	psw
	ret
