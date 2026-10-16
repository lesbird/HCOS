; hdosfs.asm - HDOS-format disks, and the HDOS view of CP/M disks
;
; Each drive (unit) A:-D: is checked the first time a name on it is
; decoded. An HDOS disk in an H17 drive is read directly through the
; BIOS (bios.asm): its files are found through its own directory and
; read by following the group chain in its GRT. HDOS disks are read
; only for now.
;
; On a CP/M disk, opening DIRECT.SYS gives a directory built from the
; CP/M directory, with a GRT whose chains give each file its size and
; the free space its size, so HDOS PIP can list CP/M disks.
;
; Formats are from the HDOS decks (LABDEF, DIRDEF, DISDEF, DEVDEF) and
; were checked against a real HDOS 2.0 disk.

NUNIT	equ	4		; units 0-3 = drives A:-D:
US.UNK	equ	0		; unit not looked at yet
US.CPM	equ	1		; CP/M disk
US.HDOS	equ	2		; HDOS disk

; Unit table entry (DEVDEF), found through S.GUP
UNT.FLG	equ	0		; device flags
UNT.SPG	equ	1		; sectors per group
UNT.GRT	equ	2		; -> GRT in memory (page aligned)
UNT.GTS	equ	4		; GRT sector
UNT.DIS	equ	6		; first directory sector
UNTLEN	equ	8

; Label, sector 9 (LABDEF)
LABSEC	equ	9
LAB.DIS	equ	03h		; first directory sector
LAB.GRT	equ	05h		; GRT sector
LAB.SPG	equ	07h		; sectors per group
LAB.SIZ	equ	0Ch		; volume size in sectors
LAB.PSS	equ	0Eh		; physical sector size (0100H)
LAB.SPT	equ	4Fh		; sectors per track (10)

; Directory: 512-byte blocks of 22 entries of 23 bytes (DISDEF, DIRDEF)
DIRELEN	equ	23
DIRENT	equ	22
DIS.ENL	equ	1FBh		; entry length
DIS.SEC	equ	1FCh		; this block's sector
DIS.LNK	equ	1FEh		; next block's sector, 0 if last
DIR.FLG	equ	0Eh
DIR.FGN	equ	10h		; first group
DIR.LGN	equ	11h		; last group
DIR.LSI	equ	12h		; sectors used in the last group
DF.EMP	equ	0FFh		; empty entry
DF.CLR	equ	0FEh		; empty, and the rest of the directory too

; Channel state for an HDOS file or a made-up directory, kept in the
; channel's FCB area.
HC.UNIT	equ	0
HC.FGN	equ	1
HC.CUR	equ	2		; current group, 0 at the end
HC.IDX	equ	3		; next sector in it
HC.LGN	equ	4
HC.LSI	equ	5
HC.SPG	equ	6
HC.GRT	equ	7		; GRT page (high byte)
HC.POS	equ	8		; made-up directory: next sector (word)

; ---- Units ----

; uinit - forget every unit's format; point each at its GRT page.
uinit:	lxi	h,ustat
	mvi	b,NUNIT
	xra	a
ui1:	mov	m,a
	inx	h
	dcr	b
	jnz	ui1
	lxi	h,unttab+UNT.GRT
	lda	pgrt+1
	mvi	b,NUNIT
ui2:	mvi	m,0
	inx	h
	mov	m,a
	inr	a
	lxi	d,UNTLEN-1
	dad	d
	dcr	b
	jnz	ui2
	lxi	h,0FFFFh		; nothing made up yet
	shld	synblk
	ret

; uent - A = unit: HL -> its unit table entry. Uses A.
uent:	add	a
	add	a
	add	a
	lxi	h,unttab
	jmp	rdadap

; udet - A = unit: find out its format. Exit A = US.CPM or US.HDOS.
udet:	sta	dunit
	lxi	h,ustat
	call	rdadap
	mov	a,m
	ora	a
	rnz				; known
	push	h
	lxi	h,0FFFFh		; psec is about to be reused
	shld	synblk
	lxi	h,0
	shld	udpb
	lda	dunit			; an H17 drive? (20 records a track)
	mov	c,a
	mvi	e,0
	mvi	a,B.SELDSK
	call	bcall
	mov	a,h
	ora	l
	jz	ud.cpm
	lxi	d,10			; DPH -> DPB
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	shld	udpb
	mov	a,m
	cpi	20
	jnz	ud.cpm
	inx	h
	mov	a,m
	ora	a
	jnz	ud.cpm
	lhld	psec			; read the label
	xchg
	lxi	h,LABSEC
	lda	dunit
	call	rdsec
	jc	ud.cpm
	mvi	a,LAB.PSS		; a believable HDOS label?
	call	labw
	mov	a,h
	dcr	a
	ora	l
	jnz	ud.cpm			; 256-byte sectors
	mvi	a,LAB.SPT
	call	labb
	cpi	10
	jnz	ud.cpm			; 10 a track
	mvi	a,LAB.SPG
	call	labb
	dcr	a
	cpi	8
	jnc	ud.cpm			; 1-8 sectors a group
	mvi	a,LAB.SIZ
	call	labw
	xchg				; DE = size
	mvi	a,LAB.DIS
	call	labw
	call	cmphd
	jnc	ud.cpm			; directory inside it
	mvi	a,LAB.GRT
	call	labw
	call	cmphd
	jnc	ud.cpm			; GRT inside it

	; HDOS disk: fill in the unit entry and read its GRT.
	lda	dunit
	call	uent
	shld	uptr
	mvi	a,LAB.SPG
	call	labb
	lhld	uptr
	inx	h
	mov	m,a
	mvi	a,LAB.GRT
	call	labw
	xchg
	lhld	uptr
	lxi	b,UNT.GTS
	dad	b
	mov	m,e
	inx	h
	mov	m,d
	mvi	a,LAB.DIS
	call	labw
	xchg
	lhld	uptr
	lxi	b,UNT.DIS
	dad	b
	mov	m,e
	inx	h
	mov	m,d
	lhld	uptr			; GRT sector -> GRT page
	lxi	b,UNT.GRT
	dad	b
	mov	e,m
	inx	h
	mov	d,m
	push	d
	mvi	a,LAB.GRT
	call	labw
	pop	d
	lda	dunit
	call	rdsec
	jc	ud.cpm
	mvi	a,US.HDOS
	jmp	ud.set

	; CP/M disk: sectors per group so its groups fit in a GRT.
ud.cpm:	call	bdsel
	call	cpmspg
	push	psw
	lda	dunit
	call	uent
	inx	h
	pop	psw
	mov	m,a
	mvi	a,US.CPM
ud.set:	pop	h
	mov	m,a
	ora	a
	ret

; labb / labw - byte / word at offset A of the label in psec.
labb:	lhld	psec
	call	rdadap
	mov	a,m
	ret
labw:	lhld	psec
	call	rdadap
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	ret

; cpmspg - sectors per group for a CP/M disk with DPB udpb: the
; smallest power of 2 that keeps its size under 220 groups.
cpmspg:	lhld	udpb
	mov	a,h
	ora	l
	mvi	a,2
	rz
	push	h
	lxi	d,5			; DSM: blocks - 1
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	inx	d
	pop	h
	inx	h			; BSH
	inx	h
	mov	b,m
	dcr	b			; blocks -> 256-byte sectors
	xchg
cs1:	dad	h
	dcr	b
	jnz	cs1
	mvi	c,1
cs2:	mov	a,h
	ora	a
	jnz	cs3
	mov	a,l
	cpi	221
	jc	cs4
cs3:	mov	a,c
	cpi	128
	jz	cs4
	ora	a			; halve the size, double the group
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	mov	a,c
	add	a
	mov	c,a
	jmp	cs2
cs4:	mov	a,c
	ret

; ---- HDOS files ----

; hlook - find dnam's file in unit dunit's directory. Exit HL -> its
; entry (in psec); CY and A = EC.* if not there.
hlook:	lxi	h,0FFFFh
	shld	synblk
	lda	dunit
	call	uent
	lxi	d,UNT.DIS
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
hl.blk:	mov	a,h
	ora	l
	jz	hl.nf
	call	rdblk
	rc
	lhld	psec
	mvi	b,DIRENT
hl.ent:	mov	a,m
	cpi	DF.CLR
	jz	hl.nf			; end of the directory
	ora	a
	jz	hl.next			; end of this block
	cpi	DF.EMP
	jz	hl.skip
	push	h
	push	b
	lxi	d,dnam+3
	mvi	c,11
	call	rcomp
	pop	b
	pop	h
	jnz	hl.skip
	ora	a			; found
	ret
hl.skip: lxi	d,DIRELEN
	dad	d
	dcr	b
	jnz	hl.ent
hl.next: lhld	psec
	lxi	d,DIS.LNK
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	jmp	hl.blk
hl.nf:	mvi	a,EC.FNF
	stc
	ret

; rdblk - read directory block HL of unit dunit into psec.
rdblk:	shld	hlblk
	lhld	psec
	xchg
	lhld	hlblk
	lda	dunit
	call	rdsec
	rc
	lhld	psec
	inr	h
	xchg
	lhld	hlblk
	inx	h
	lda	dunit
	jmp	rdsec

; hopen - open dnam's file on HDOS unit dunit for reading on channel
; chp.
hopen:	call	hlook
	rc
	xchg				; DE -> directory entry
	call	hstate
	lda	dunit
	mov	m,a			; HC.UNIT
	lxi	h,DIR.FGN
	dad	d
	mov	b,m			; FGN
	inx	h
	mov	c,m			; LGN
	inx	h
	mov	e,m			; LSI
	lhld	hst
	inx	h
	mov	m,b			; HC.FGN
	inx	h
	mov	m,b			; HC.CUR
	inx	h
	mvi	m,0			; HC.IDX
	inx	h
	mov	m,c			; HC.LGN
	inx	h
	mov	m,e			; HC.LSI
	lda	dunit
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
	mvi	a,CM.HRD
	call	setmode
	ora	a
	ret

; hstate - HL and hst -> the state of channel chp. hfld - HL -> field
; A of it. Both keep BC, DE.
hstate:	lhld	chp
	inx	h			; CH.FCB
	shld	hst
	ret
hfld:	lhld	hst
	jmp	rdadap

; hnext - HDOS file on channel chp: HL = its next sector number, and
; move past it. CY and A = EC.EOF at the end. Keeps DE.
hnext:	call	hstate
	mvi	a,HC.CUR
	call	hfld
	mov	a,m
	ora	a
	jz	hn.eof			; empty file, or past the end
	sta	hcur
	mvi	a,HC.IDX
	call	hfld
	mov	a,m
	sta	hidx
	mvi	a,HC.LGN		; in the last group, LSI sectors
	call	hfld
	lda	hcur
	cmp	m
	jnz	hn.ok
	mvi	a,HC.LSI
	call	hfld
	lda	hidx
	cmp	m
	jnc	hn.eof
hn.ok:	mvi	a,HC.SPG
	call	hfld
	mov	a,m
	sta	hspg
	push	d
	lda	hcur			; sector = group * SPG + index
	mov	e,a
	mvi	d,0
	lda	hspg
	call	rmu86
	pop	d
	lda	hidx
	call	rdadap
	push	h
	lda	hidx			; advance
	inr	a
	lxi	h,hspg
	cmp	m
	jnz	hn.st
	mvi	a,HC.GRT		; next group: GRT[current]
	call	hfld
	mov	h,m
	lda	hcur
	mov	l,a
	mov	a,m
	push	psw
	mvi	a,HC.CUR
	call	hfld
	pop	psw
	mov	m,a
	xra	a
hn.st:	push	psw
	mvi	a,HC.IDX
	call	hfld
	pop	psw
	mov	m,a
	pop	h
	ora	a
	ret
hn.eof:	mvi	a,EC.EOF
	stc
	ret

; hread - read B sectors of the HDOS file on chp into DE.
hread:	mov	a,b
	ora	a
	rz
	push	b
	call	hnext
	jc	hr.eof
	push	d
	push	h
	mvi	a,HC.UNIT
	call	hfld
	mov	a,m
	pop	h
	call	rdsec
	pop	d
	pop	b
	rc
	inr	d
	dcr	b
	jmp	hread
hr.eof:	pop	b
	stc
	ret

; hposit - HDOS file on chp: position before sector BC.
hposit:	call	hstate
	mvi	a,HC.FGN
	call	hfld
	mov	a,m
	inx	h			; HC.CUR = FGN
	mov	m,a
	inx	h			; HC.IDX = 0
	mvi	m,0
hp1:	mov	a,b
	ora	c
	rz
	push	b
	call	hnext
	pop	b
	rc				; EC.EOF, BC = sectors short
	dcx	b
	jmp	hp1

; ---- Data ----
ustat:	ds	NUNIT			; US.* for each unit
dunit:	db	0			; unit being worked on
udpb:	dw	0
uptr:	dw	0
hlblk:	dw	0
hst:	dw	0
hcur:	db	0
hidx:	db	0
hspg:	db	0
synblk:	dw	0			; block now in psec (FFFF = none)
synunit: db	0
synhalf: db	0
synskip: dw	0
synn:	db	0			; entries in the block
syni:	db	0
synep:	dw	0
synlsi:	db	0
syng:	db	0			; next free group number
syngrt:	dw	0
cfbsh:	db	0

; Unit table (DEVDEF UNT.*): flags, SPG, GRT, GRT sector, dir sector
unttab:	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0
