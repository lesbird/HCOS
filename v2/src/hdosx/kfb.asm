; kfb.asm - CP/M FCB calls on HDOS disks (the "KFB" layer)
;
; The BDOS offers each FCB call to kxhook before it selects the drive.
; For an HDOS disk the call is carried out here with the HDOS file
; system modules (hdosfs, hdoswr, hdosdir):
;   - An open file gets a slot in kslots, laid out like an HDOS.COM
;     channel, so those modules work on it unchanged. The FCB's map
;     says which slot ("K", slot number); the rest of the FCB keeps its
;     CP/M meaning.
;   - Record r is the half (r AND 1) of HDOS sector r / 2, through
;     dbuf. Writes read the sector, change the half and write it back;
;     past the end they add sectors.
;   - Searches give one directory entry a file, built in the DMA buffer.
; HDOS has no user numbers: every user sees the same files.

NKSLOT	equ	4
KSIG	equ	'K'

; FCB offsets (as in the BDOS)
F.T1	equ	9
F.T2	equ	10
F.EX	equ	12
F.S2	equ	14
F.RC	equ	15
F.MAP	equ	16
F.CR	equ	32
F.R0	equ	33

; kxhook - the BDOS offers an FCB call: A = drive, C = function, DE =
; FCB, HL = DMA. CY: not an HDOS disk, so the BDOS goes on. Else A =
; the result, NC. It runs on its own stack: the BDOS's is small.
kxhook:	shld	kdma
	lxi	h,0
	dad	sp
	shld	kxsp
	lxi	sp,kxstk
	lhld	kdma
	call	kxh1
	lhld	kxsp			; (flags and A pass through)
	sphl
	ret
kxh1:	cpi	NUNIT
	cmc
	rc
	sta	kdrv
	mov	a,c
	sta	kfn
	shld	kdma
	xchg
	shld	kfcb
	lda	kdrv
	call	udet
	cpi	US.HDOS
	stc
	rnz
	lda	kdrv
	sta	dunit
	lda	kfn			; find the function
	mov	c,a
	lxi	h,kftab
kh1:	mov	a,m
	ora	a
	stc
	rz				; not one of ours: the BDOS's
	inx	h
	mov	e,m
	inx	h
	mov	d,m
	inx	h
	cmp	c
	jnz	kh1
	xchg
	call	kgo
	ora	a
	ret
kgo:	pchl

kftab:	db	15
	dw	kopen
	db	16
	dw	kclose
	db	17
	dw	ksf
	db	18
	dw	ksn
	db	19
	dw	kdel
	db	20
	dw	krds
	db	21
	dw	kwrs
	db	22
	dw	kmake
	db	23
	dw	kren
	db	30
	dw	kattr
	db	33
	dw	krdr
	db	34
	dw	kwrr
	db	35
	dw	ksize
	db	27
	dw	kalv
	db	31
	dw	kdpb
	db	40
	dw	kwrr
	db	0

; ---- Names and slots ----

; kname - dnam = the HDOS form of the CP/M name at HL: device SY, unit
; dunit, name and type with blanks as 0 and no attribute bits.
kname:	push	h
	lxi	h,dnam
	mvi	m,'S'
	inx	h
	mvi	m,'Y'
	inx	h
	lda	dunit
	mov	m,a
	inx	h
	xchg
	pop	h
	mvi	b,11
kn1:	mov	a,m
	ani	7Fh
	cpi	' '
	jnz	kn2
	xra	a
kn2:	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	kn1
	ret

; kfname - dnam = the FCB's name.
kfname:	lhld	kfcb
	inx	h
	jmp	kname

; kfcbf - HL -> field A of the FCB. Uses A.
kfcbf:	lhld	kfcb
	jmp	rdadap

; kalloc - chp = a free slot, A = its number. CY if none.
kalloc:	lxi	h,kslots
	mvi	b,0
ka1:	mov	a,m
	ora	a
	jz	ka2
	lxi	d,CHLEN
	dad	d
	inr	b
	mov	a,b
	cpi	NKSLOT
	jc	ka1
	stc
	ret
ka2:	shld	chp
	mov	a,b
	sta	kslotn
	ret

; kslot - chp = the FCB's slot (from its map). CY if it has none.
kslot:	mvi	a,F.MAP
	call	kfcbf
	mov	a,m
	cpi	KSIG
	stc
	rnz
	inx	h
	mov	a,m
	cpi	NKSLOT
	cmc
	rc
	lxi	h,kslots
	lxi	d,CHLEN
ks1:	ora	a
	jz	ks2
	dad	d
	dcr	a
	jmp	ks1
ks2:	shld	chp
	mov	a,m
	ora	a
	stc
	rz				; closed
	inx	h			; its unit
	mov	a,m
	sta	dunit
	ora	a
	ret

; kopened - the slot chp is in use for the FCB: name it, mark the FCB.
kopened: lhld	chp			; the slot's name
	lxi	d,CH.DNAM
	dad	d
	xchg
	lxi	h,dnam
	mvi	b,14
	call	move
	mvi	a,F.MAP			; the FCB's map: "K", slot
	call	kfcbf
	mvi	m,KSIG
	inx	h
	lda	kslotn
	mov	m,a
	xra	a
	ret

; ---- Open, make, close ----

; f15 - open: FFH if there is no such file.
kopen:	call	kfname
	call	hlook
	jc	kff
	call	kalloc
	jc	kff
	call	hopen			; for reading: writing upgrades it
	jc	kfree
	call	kopened
	call	hlook			; record count for its extent
	call	ksecs
	dad	h			; records
	push	h
	call	krecseq			; HL = record the FCB is at
	mov	a,l
	ani	80h
	mov	l,a			; first record of its extent
	xchg
	pop	h
	mov	a,l			; records left from there
	sub	e
	mov	l,a
	mov	a,h
	sbb	d
	mov	h,a
	mvi	a,0
	jc	ko1			; none
	mov	a,h
	ora	a
	mvi	a,128
	jnz	ko1
	mov	a,l
	cpi	128
	jc	ko1
	mvi	a,128
ko1:	push	psw
	mvi	a,F.RC
	call	kfcbf
	pop	psw
	mov	m,a
	xra	a
	ret
kfree:	lhld	chp
	mvi	m,CM.CLS
kff:	mvi	a,0FFh
	ret

; f22 - make. As on CP/M (not HDOS) the file is in the directory at
; once, empty, replacing one of that name; it stays open as an update.
kmake:	call	kfname
	call	kalloc
	jc	kff
	xra	a
	sta	chnoex
	call	hcreate
	jc	kfree
	call	kopened
	call	hclose			; enter it now
	jc	kfree
	mvi	a,CM.HUP
	call	setmode
	mvi	a,F.RC
	call	kfcbf
	mvi	m,0
	xra	a
	ret

; f16 - close: a written file goes into the directory.
kclose:	call	kslot
	jc	kff
	lhld	chp
	mov	a,m
	cpi	CM.HWR
	jc	kc1			; only read: nothing to do
	call	hclose
	jc	kc2
kc1:	lhld	chp
	mvi	m,CM.CLS
	xra	a
	ret
kc2:	lhld	chp
	mvi	m,CM.CLS
	jmp	kff

; ---- Reading and writing ----

; f20 / f33 - read sequential / random.
krds:	call	kslot
	jc	k1
	call	krecseq
	push	h
	call	krd1
	pop	h
	rc
	jmp	kadv
krdr:	call	kslot
	jc	k1
	call	krecran
	rc
	call	kset
	jmp	krd1

; krd1 - record HL to the DMA buffer. CY, A = 1 if there is none.
krd1:	call	ksec			; BC = sector, A = half
	sta	khalf
	call	kgets
	jc	k1c
	call	khalfp			; HL -> the half in dbuf
	xchg
	lhld	kdma
	xchg
	mvi	b,128
	call	move
	xra	a
	ret
k1c:	mvi	a,1
	stc
	ret
k1:	mvi	a,1
	ret

; kgets - dbuf = sector BC of the slot's file. CY if past the end.
kgets:	call	hposit
	rc
	call	hnext			; HL = its sector on the disk
	rc
; kg0 - dbuf = sector HL of unit dunit, unless it's there already. CY
; on a read error.
kg0:	lda	kcunit
	push	h
	lxi	h,dunit
	cmp	m
	pop	h
	jnz	kg1
	xchg
	lhld	kclsn
	call	cmphd
	xchg
	rz
kg1:	shld	kclsn
	lda	dunit
	sta	kcunit
	lxi	d,dbuf
	call	rdsec
	rnc
	mvi	a,0FFh			; nothing good in dbuf
	sta	kcunit
	stc
	ret

; f21 / f34 / f40 - write sequential / random.
kwrs:	call	kwok
	rc
	call	krecseq
	push	h
	call	kwr1
	pop	h
	rc
	jmp	kadv
kwrr:	call	kwok
	rc
	call	krecran
	rc
	call	kset
	jmp	kwr1

; kwok - the FCB's slot, writable: a file opened for reading becomes an
; update now, unless it's write protected. CY, A = result if not.
kwok:	call	kslot
	mvi	a,1
	rc
	lhld	chp
	mov	a,m
	cpi	CM.HRD
	jnz	kw0
	call	hlook
	call	hwpchk
	mvi	a,1
	rc
	mvi	a,CM.HUP
	call	setmode
kw0:	xra	a
	ret

; kwr1 - write the DMA buffer as record HL. CY, A = 2 if the disk is
; full, 1 for other errors.
kwr1:	call	ksec
	sta	khalf
	push	b
	call	hposit
	pop	d			; DE = the sector
	jc	kw.gap			; past the end: BC sectors missing
	push	d
	call	hnext
	pop	b
	jc	kw.add			; just at the end: add it
	push	b			; there: change half of it
	call	kg0
	pop	b
	jc	kw.err
	call	kput
	call	hposit
	lxi	d,dbuf
	call	hwsec
	jc	kw.err
	xra	a
	ret
kw.gap:	mov	a,b			; add the missing sectors, zero
	ora	c
	jz	kw.add
	push	b
	call	kzero
	lxi	d,dbuf
	call	hwsec
	pop	b
	jc	kw.err
	dcx	b
	jmp	kw.gap
kw.add:	call	kzero			; and this one
	call	kput
	lxi	d,dbuf
	call	hwsec
	jc	kw.err
	xra	a
	ret
kw.err:	cpi	EC.EOM
	mvi	a,2
	stc
	rz
	mvi	a,1
	stc
	ret

; kzero - dbuf = zeros (and nothing cached in it).
kzero:	lxi	h,dbuf
	lxi	b,256
	call	zfill
	mvi	a,0FFh
	sta	kcunit
	ret

; kput - the DMA buffer into its half of dbuf.
kput:	call	khalfp
	xchg
	lhld	kdma
	mvi	b,128
	jmp	move

; khalfp - HL -> the half khalf of dbuf.
khalfp:	lxi	h,dbuf
	lda	khalf
	ora	a
	rz
	mvi	l,(dbuf+128) and 0FFh
	mvi	h,(dbuf+128) shr 8
	ret

; ksec - record HL: BC = its sector, A = its half.
ksec:	mov	a,l
	ani	1
	push	psw
	ora	a
	mov	a,h
	rar
	mov	b,a
	mov	a,l
	rar
	mov	c,a
	pop	psw
	ret

; krecseq - HL = the FCB's record: (S2 * 32 + EX) * 128 + CR.
krecseq: mvi	a,F.S2
	call	kfcbf
	mov	a,m
	ani	0Fh
	add	a			; S2 * 32 + EX, times 128 = << 7
	add	a
	add	a
	add	a
	add	a
	mov	d,a
	mvi	a,F.EX
	call	kfcbf
	mov	a,m
	ani	1Fh
	ora	d
	mov	h,a			; H:L = (S2*32+EX) << 8
	mvi	l,0
	ora	a			; >> 1
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	push	h
	mvi	a,F.CR
	call	kfcbf
	mov	a,m
	pop	h
	ora	l
	mov	l,a
	ret

; krecran - HL = the FCB's random record. CY, A = 6 past the end.
krecran: mvi	a,F.R0+2
	call	kfcbf
	mov	a,m
	ora	a
	mvi	a,6
	stc
	rnz
	dcx	h
	mov	a,m
	dcx	h
	mov	l,m
	mov	h,a
	ora	a
	ret

; kadv - the FCB on to record HL + 1 (sequential I/O).
kadv:	inx	h
; kset - the FCB at record HL: S2, EX, CR. Keeps HL.
kset:	push	h
	call	kset1
	pop	h
	ret
kset1:	push	h
	mov	a,l			; CR = record AND 7FH
	ani	7Fh
	push	psw
	mvi	a,F.CR
	call	kfcbf
	pop	psw
	mov	m,a
	pop	h
	push	h
	mov	a,l			; EX = (record >> 7) AND 1FH
	ral
	mov	a,h
	ral
	ani	1Fh
	push	psw
	mvi	a,F.EX
	call	kfcbf
	pop	psw
	mov	m,a
	pop	h
	mov	a,h			; S2 = record >> 12
	rrc
	rrc
	rrc
	rrc
	ani	0Fh
	push	psw
	mvi	a,F.S2
	call	kfcbf
	pop	psw
	mov	m,a
	xra	a
	ret

; ---- Directory ----

; ksecs - HL -> directory entry (in psec): HL = the file's sectors,
; (groups - 1) * SPG + LSI.
ksecs:	push	h
	lxi	d,DIR.FGN
	dad	d
	mov	a,m
	inx	h
	mov	c,m			; C = LGN
	inx	h
	mov	b,m			; B = LSI
	pop	h
	mov	e,a			; E = group
	ora	a
	lxi	h,0
	rz				; no groups: empty
	push	b
	lda	dunit
	call	uent
	inx	h
	mov	a,m
	sta	kspg
	inx	h
	inx	h
	mov	h,m			; the GRT
	pop	b
	mvi	d,0			; D = groups
ksc1:	inr	d
	mov	a,e
	cmp	c
	jz	ksc2
	mov	l,e
	mov	e,m
	mov	a,e
	ora	a
	jnz	ksc1
ksc2:	dcr	d
	mov	e,d
	mvi	d,0
	lda	kspg
	push	b
	call	rmu86
	pop	b
	mov	a,b
	jmp	rdadap

; kmatch - Z if the directory entry at HL matches the FCB's name
; ("?" matches anything).
kmatch:	push	h
	xchg
	lhld	kfcb
	inx	h
	mvi	b,11
km1:	mov	a,m
	ani	7Fh
	cpi	'?'
	jz	km2
	mov	c,a
	ldax	d
	ora	a
	jnz	km1a
	mvi	a,' '
km1a:	cmp	c
	jnz	km3
km2:	inx	h
	inx	d
	dcr	b
	jnz	km1
km3:	pop	h
	ret

; kfirst / knext - HL -> the next directory entry matching the FCB,
; from the start or from where the last one was. CY if no more.
kfirst:	lda	dunit
	call	uent
	lxi	d,UNT.DIS
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	shld	kblk
	xra	a
	sta	kidx
knext:	lhld	kblk
	mov	a,h
	ora	l
	stc
	rz				; no more blocks
	xchg				; the block in psec?
	lhld	synblk
	call	cmphd
	jz	kn.in
	xchg
	call	rdblk
	rc
	lhld	kblk
	shld	synblk
kn.in:	lda	kidx
	cpi	DIRENT
	jnc	kn.nb
	inr	a
	sta	kidx
	dcr	a
	mov	e,a
	mvi	d,0
	mvi	a,DIRELEN
	call	rmu86
	xchg
	lhld	psec
	dad	d
	mov	a,m
	cpi	DF.CLR
	stc
	rz				; the end of the directory
	ora	a
	jz	kn.nb			; the end of this block
	cpi	DF.EMP
	jz	knext
	call	kmatch
	jnz	knext
	ora	a
	ret
kn.nb:	lhld	psec			; on to the next block
	lxi	d,DIS.LNK
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	shld	kblk
	xra	a
	sta	kidx
	jmp	knext

; f17 / f18 - search: a CP/M directory entry for the match, in the
; DMA buffer as entry 0.
ksf:	call	kfirst
	jmp	ks.got
ksn:	call	knext
ks.got:	jc	kff
	push	h
	lhld	kdma			; entries 1-3 empty
	lxi	d,32
	dad	d
	mvi	b,96
ksg1:	mvi	m,0E5h
	inx	h
	dcr	b
	jnz	ksg1
	lhld	kdma			; entry 0: user 0, the name
	lxi	b,32
	call	zfill
	pop	h
	push	h
	lhld	kdma
	inx	h
	xchg
	pop	h
	push	h
	mvi	b,11
ksg2:	mov	a,m
	ora	a
	jnz	ksg3
	mvi	a,' '
ksg3:	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	ksg2
	pop	h			; flags: W -> R/O, S -> SYS
	push	h
	lxi	d,DIR.FLG
	dad	d
	mov	b,m
	lhld	kdma
	lxi	d,F.T1
	dad	d
	mov	a,b
	ani	DF.WP
	jz	ksg4
	mov	a,m
	ori	80h
	mov	m,a
ksg4:	inx	h
	mov	a,b
	ral
	jnc	ksg5
	mov	a,m
	ori	80h
	mov	m,a
ksg5:	pop	h			; record count, up to 128
	call	ksecs
	dad	h
	mov	a,h
	ora	a
	mvi	a,128
	jnz	ksg6
	mov	a,l
	cpi	128
	jc	ksg6
	mvi	a,128
ksg6:	push	psw
	lhld	kdma
	lxi	d,F.RC
	dad	d
	pop	psw
	mov	m,a
	adi	7			; a block number in the map for each
	rrc				; 1K, for STAT's sizes
	rrc
	rrc
	ani	1Fh
	jz	ksg8
ksg7:	inx	h
	mvi	m,1
	dcr	a
	jnz	ksg7
ksg8:	xra	a
	ret

; f19 - delete every match. FFH if there was none.
kdel:	mvi	a,0FFh
	sta	kres
kd1:	call	kfirst
	jc	kd2
	lxi	d,dnam+3		; its name
	mvi	b,11
	call	move
	call	hdelete
	jc	kff
	xra	a
	sta	kres
	jmp	kd1
kd2:	lda	kres
	ret

; f23 - rename to the name at FCB+16.
kren:	call	kfname			; old name
	lxi	h,dnam+3
	lxi	d,hrold
	mvi	b,11
	call	move
	mvi	a,17			; new name
	call	kfcbf
	call	kname
	call	hren2
	jc	kff
	xra	a
	ret

; f30 - attributes: R/O -> W, SYS -> S.
kattr:	call	kfname
	call	hlook
	jc	kff
	lxi	d,DIR.FLG
	dad	d
	mov	a,m
	ani	0FFh-DF.WP-80h
	mov	b,a
	mvi	a,F.T1
	call	kfcbf
	mov	a,m
	ani	80h
	jz	kat1
	mvi	a,DF.WP
	ora	b
	mov	b,a
kat1:	inx	h
	mov	a,m
	ani	80h
	ora	b
	mov	b,a
	call	hlook			; (kfcbf moved HL)
	lxi	d,DIR.FLG
	dad	d
	mov	m,b
	call	wrdir
	jc	kff
	xra	a
	ret

; f35 - file size in records.
ksize:	call	kfname
	call	hlook
	jc	kff
	call	ksecs
	dad	h
	push	h
	mvi	a,F.R0
	call	kfcbf
	pop	d
	mov	m,e
	inx	h
	mov	m,d
	inx	h
	mvi	m,0
	xra	a
	ret

; f27 / f31 - an allocation vector and a DPB made up for the HDOS disk,
; so that STAT's figures mean something: 1K blocks, as many as the
; volume has sectors for, with the free ones (the GRT's free chain) at
; the end. The address goes where the BDOS said (DE, in kfcb).
kalv:	lxi	b,kav
	jmp	kdk
kdpb:	lxi	b,kdp
kdk:	push	b
	lxi	h,kav
	lxi	b,KAVLEN
	call	zfill
	lxi	h,LABSEC		; the volume's size, from its label
	call	kg0
	jc	kdk.x
	lhld	dbuf+LAB.SIZ
	call	kq4			; DSM = sectors / 4 - 1
	dcx	h
	shld	kdp+5
	lda	dunit			; count the directory's blocks
	call	uent
	push	h
	lxi	d,UNT.DIS
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	lxi	b,0
kdk1:	mov	a,h
	ora	l
	jz	kdk2
	push	b
	call	rdblk
	pop	b
	jc	kdk.y
	lhld	psec
	lxi	d,DIS.LNK
	dad	d
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	inr	c
	jnz	kdk1
kdk2:	mvi	a,DIRENT		; DRM = blocks * 22 - 1
	mov	d,b
	mov	e,c
	call	rmu86
	dcx	h
	shld	kdp+7
	pop	h			; the unit: count the free groups
	push	h
	inx	h			; (UNT.SPG)
	mov	e,m
	inx	h			; (UNT.GRT)
	inx	h
	mov	h,m
	mvi	l,0
	mvi	c,0
kdk3:	mov	a,m			; GRT[g] = the next free one
	ora	a
	jz	kdk4
	mov	l,a
	inr	c
	jnz	kdk3			; (a loop in the chain stops at 256)
kdk4:	mov	a,c
	mvi	d,0
	call	rmu86			; free sectors
	call	kq4
	xchg				; DE = free blocks
	lhld	kdp+5			; BC = used = DSM + 1 - free
	inx	h
	mov	a,l
	sub	e
	mov	c,a
	mov	a,h
	sbb	d
	mov	b,a
	lxi	h,kav			; set the first BC bits of kav
	mvi	d,80h
kdk5:	mov	a,b
	ora	c
	jz	kdk.y
	mov	a,m
	ora	d
	mov	m,a
	mov	a,d
	rrc
	mov	d,a
	jnc	kdk6
	inx	h
kdk6:	dcx	b
	jmp	kdk5
kdk.y:	pop	h			; (the unit)
	lxi	h,0FFFFh		; psec was used
	shld	synblk
kdk.x:	pop	d			; the vector or the DPB
	rc
	lhld	kfcb
	mov	m,e
	inx	h
	mov	m,d
	xra	a
	ret
; kq4 - HL = HL / 4.
kq4:	call	kq2
kq2:	ora	a
	mov	a,h
	rar
	mov	h,a
	mov	a,l
	rar
	mov	l,a
	ret

; kxreset - at every boot: forget what is known about the disks and
; close every slot.
kxreset: call	uinit
	xra	a			; drives are new to the BIOS again
	sta	rsseen
	lxi	h,kslots
	lxi	b,NKSLOT*CHLEN
	call	zfill
	mvi	a,0FFh
	sta	kcunit
	ret
