; files.asm - HDOS file names, channels and the file SCALLs
;
; HDOS names are [DEV[u]:]NAME[.EXT]. Devices:
;   SYu: DKu:  disk drive u (SY0: = A:, SY1: = B:, ...)
;   A: .. H:   CP/M drive letters are accepted too
;   TT:        console
;   LP:        CP/M list device
; With no device given and the default device SY0, the file is on the
; current CP/M drive.
;
; Channels -1 to 5 each hold a CP/M FCB. Files are read and written a
; 256-byte HDOS sector at a time as two 128-byte CP/M records, by
; random record number, so .POSIT is just a new record number.
;
; As on HDOS, a file opened with .OPENW replaces the old one only at
; .CLOSE: until then it is written as NAME.$$$, and .CLEAR (or exiting
; without closing) throws it away.

	include	hchan.inc

finit:	lhld	pchtab
	lxi	b,NCHAN*CHLEN
fi1:	mvi	m,0
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	fi1
	ret

; ---- File names ----

; decode - decode the HDOS name at HL using the 6-byte default block
; at BC ('SY0ABS' style; zeros for none). Fills dnam and dexpl.
; Exit HL at the delimiter, or CY and A = EC.*.
decode:	push	b
	lxi	d,dnam			; clear dnam
	mvi	b,14
	xra	a
de0:	stax	d
	inx	d
	dcr	b
	jnz	de0
	sta	dexpl
	pop	b
	push	b			; default device and unit
	ldax	b
	sta	dnam
	inx	b
	ldax	b
	sta	dnam+1
	inx	b
	ldax	b
	ora	a
	jz	de0a
	sui	'0'
de0a:	sta	dnam+2
	inx	b			; default extension
	lxi	d,dnam+11
	push	h
	mov	h,b
	mov	l,c
	mvi	b,3
	call	move
	pop	h
	pop	b

de1:	mov	a,m			; skip blanks
	cpi	' '
	jnz	de2
	inx	h
	jmp	de1
de2:	call	token			; first token
	mov	a,m
	cpi	':'
	jz	de2a
	; HDOS 2.0 PIP puts the unit in as a binary byte ("SY<1>:"),
	; which real HDOS rejects. Take it, so PIP can list any unit.
	ora	a
	jz	de5
	cpi	8
	jnc	de5
	inx	h
	mov	a,m
	dcx	h
	cpi	':'
	jnz	de5
	lda	tokn
	cpi	2
	jnz	de5
	mov	a,m
	adi	'0'
	sta	tokb+2
	mvi	a,3
	sta	tokn
	inx	h
de2a:
	; it was a device: 2 letters + optional unit, or a drive letter
	inx	h
	mvi	a,1
	sta	dexpl
	lda	tokn
	cpi	1
	jz	de3
	lda	tokb			; 2 letters
	call	isalpha
	jc	de.idn
	sta	dnam
	lda	tokb+1
	call	isalpha
	jc	de.idn
	sta	dnam+1
	xra	a
	sta	dnam+2
	lda	tokn
	cpi	2
	jz	de4
	cpi	3
	jnz	de.idn
	lda	tokb+2			; unit digit 0-7
	sui	'0'
	cpi	8
	jnc	de.idn
	sta	dnam+2
	jmp	de4
de3:	lda	tokb			; CP/M drive letter A-H = SYu:
	sui	'A'
	cpi	8
	jnc	de.idn
	sta	dnam+2
	mvi	a,'S'
	sta	dnam
	mvi	a,'Y'
	sta	dnam+1
de4:	call	token			; the name
de5:	lda	tokn
	ora	a
	jz	de6			; no name
	cpi	9
	jnc	de.ifn
	lda	tokb
	call	isalpha
	jc	de.ifn
	push	h
	lxi	h,tokb
	lxi	d,dnam+3
	mvi	b,8
	call	move
	pop	h
de6:	mov	a,m			; extension?
	cpi	'.'
	jnz	de7
	inx	h
	call	token
	lda	tokn
	cpi	4
	jnc	de.ifn
	push	h
	lxi	h,tokb
	lxi	d,dnam+11
	mvi	b,3
	call	move
	pop	h
de7:	mov	a,m			; must end at a delimiter
	ora	a
	rz
	cpi	' '
	rz
	cpi	','
	rz
	cpi	'='
	rz
	cpi	'/'
	rz
de.ifn:	mvi	a,EC.IFN
	stc
	ret
de.idn:	mvi	a,EC.IDN
	stc
	ret

; token - collect letters and digits at HL (mapped to upper case)
; into tokb, zero padded to 8, length in tokn (9 if longer than 8).
token:	push	h
	lxi	h,tokb
	mvi	b,9
	xra	a
to0:	mov	m,a
	inx	h
	dcr	b
	jnz	to0
	pop	h
	mvi	b,0			; length
to1:	mov	a,m
	call	ucase
	call	isalnum
	jc	to3
	mov	c,a
	mov	a,b
	cpi	9
	jnc	to2			; too long: count it, don't store
	push	h
	lxi	h,tokb
	mov	e,b
	mvi	d,0
	dad	d
	mov	m,c
	pop	h
	inr	b
to2:	inx	h
	jmp	to1
to3:	mov	a,b
	sta	tokn
	ret

ucase:	cpi	'a'
	rc
	cpi	'z'+1
	rnc
	sui	20h
	ret

; isalpha / isalnum - NC if A is a letter (or digit).
isalnum: cpi	'0'
	rc
	cpi	'9'+1
	cmc
	rnc
isalpha: cpi	'A'
	rc
	cpi	'Z'+1
	cmc
	ret

; dkind - kind of the device in dnam: A = DK.*, and for a disk ddrv =
; the FCB drive byte. CY and A = EC.UND if unknown.
dkind:	lhld	dnam			; L, H = the 2 letters
	mov	a,l
	cpi	'S'
	jnz	dk1
	mov	a,h
	cpi	'Y'
	jz	dk.dsk
dk1:	mov	a,l
	cpi	'D'
	jnz	dk2
	mov	a,h
	cpi	'K'
	jz	dk.dsk
dk2:	mov	a,l
	cpi	'T'
	jnz	dk3
	mov	a,h
	cpi	'T'
	mvi	a,DK.TT
	rz
dk3:	mov	a,l
	cpi	'L'
	jnz	dk.und
	mov	a,h
	cpi	'P'
	mvi	a,DK.LP
	rz
dk.und:	mvi	a,EC.UND
	stc
	ret
dk.dsk:	lda	dexpl			; no device given and unit 0:
	ora	a			; the current CP/M drive's unit
	jnz	dk.d1
	lda	dnam+2
	ora	a
	jnz	dk.d1
	mvi	c,DRV_GET
	call	BDOS
	sta	dnam+2
dk.d1:	lda	dnam+2
	cpi	NUNIT
	mvi	a,EC.UUN
	cmc
	rc
	lda	dnam+2
	inr	a
	sta	ddrv
	dcr	a
	call	udet			; which format?
	cpi	US.HDOS
	mvi	a,DK.HDOS
	rz
	mvi	a,DK.DISK
	ora	a
	ret

; mkfcb - build a fresh FCB at DE from ddrv and the name in dnam.
mkfcb:	push	d
	mov	h,d			; clear it
	mov	l,e
	mvi	b,FCBLEN
	xra	a
mf0:	mov	m,a
	inx	h
	dcr	b
	jnz	mf0
	lda	ddrv
	stax	d
	inx	d
	lxi	h,dnam+3		; name and type, zero -> blank
	mvi	b,11
mf1:	mov	a,m
	ora	a
	jnz	mf2
	mvi	a,' '
mf2:	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	mf1
	pop	d
	ret

; parsenm - HL = name, BC = default block, DE = FCB to fill: decode a
; disk file name. Exit HL past the name; CY and A = EC.* on error.
parsenm: mvi	a,0FFh
	sta	dkres
	push	d
	call	decode
	pop	d
	rc
	push	h
	push	d
	call	dkind
	pop	d
	pop	h
	rc
	sta	dkres
	ora	a
	jz	pn1
	cpi	DK.HDOS
	mvi	a,EC.WP			; HDOS disks are read only
	stc
	rz
	mvi	a,EC.DNS		; not a disk
	stc
	ret
pn1:	lda	dnam+3
	ora	a
	mvi	a,EC.IFN
	stc
	rz				; no name
	push	h
	call	mkfcb
	pop	h
	ora	a
	ret

; ---- Channels ----

; chptr - A = channel (-1..5): HL -> its entry, chp set. CY, A =
; EC.ICN if out of range. Keeps BC, DE.
chptr:	inr	a
	cpi	NCHAN
	jc	cp1
	mvi	a,EC.ICN
	stc
	ret
cp1:	push	d
	lhld	pchtab
	lxi	d,CHLEN
cp2:	ora	a
	jz	cp3
	dad	d
	dcr	a
	jmp	cp2
cp3:	shld	chp
	pop	d
	ret

; chopen - A = channel, HL = name, DE = default block: decode the name
; into the (closed) channel. Exit A = DK.*, HL past the name, chp set,
; FCB built for a disk file. CY and A = EC.* on error.
chopen:	push	h
	call	chptr
	pop	h
	rc
	push	h
	lhld	chp
	mov	a,m
	pop	h
	ora	a
	mvi	a,EC.CNA
	stc
	rnz
	mov	b,d			; BC = default block
	mov	c,e
	call	decode
	rc
	shld	chname
	call	dkind
	rc
	sta	chkind
	cpi	DK.HDOS
	jz	cho0
	ora	a
	jnz	cho1			; device: nothing more
cho0:	lda	dnam+3
	ora	a
	mvi	a,EC.IFN
	stc
	rz
	lda	chkind
	ora	a
	jnz	cho2			; HDOS disk: no FCB
	lhld	chp
	lxi	d,CH.FCB
	dad	d
	xchg
	call	mkfcb
cho2:	lhld	chp			; keep the decoded name
	lxi	d,CH.DNAM
	dad	d
	xchg
	lxi	h,dnam
	mvi	b,14
	call	move
cho1:	lhld	chname
	lda	chkind
	ora	a
	ret

; chfcb - DE -> FCB of channel chp.
chfcb:	lhld	chp
	lxi	d,CH.FCB
	dad	d
	xchg
	ret

; setmode - set chp's mode to A.
setmode: lhld	chp
	mov	m,a
	ret

; ---- .OPENR .OPENU .OPENW .OPENC: A = channel, HL = name, DE =
; default block (.OPENC: BC = sectors). Exit HL past the name. ----

sopenr:	sta	chnum
	mvi	a,CM.RD
	jmp	sopn
sopenu:	sta	chnum
	mvi	a,CM.UPD
sopn:	sta	chnew
	mov	a,b			; keep BC
	sta	chbc
	mov	a,c
	sta	chbc+1
	lda	chnum
	call	chopen
	jc	sopx
	cpi	DK.HDOS
	jz	sophd
	cpi	DK.DISK
	jnz	sopdev
	lda	chnew			; DIRECT.SYS of a CP/M disk is
	cpi	CM.RD			; made up
	jnz	sop1
	call	isdir
	jnz	sop1
	call	synopen
	ora	a
	jmp	sopx
sop1:	call	chfcb
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	mvi	a,EC.FNF
	stc
	jz	sopx
	lda	chnew
	call	setmode
	ora	a
sopx:	push	psw
	lda	chbc
	mov	b,a
	lda	chbc+1
	mov	c,a
	pop	psw
	lhld	chname
	ret

; HDOS disk: read, or update.
sophd:	call	hopen
	jc	sopx
	lda	chnew
	cpi	CM.RD
	jz	sopx
	call	hlook			; update: not if write protected
	call	hwpchk
	jc	sopwp
	mvi	a,CM.HUP
	call	setmode
	ora	a
	jmp	sopx
sopwp:	push	psw
	mvi	a,CM.CLS
	call	setmode
	pop	psw
	jmp	sopx

; TT: or LP:
sopdev:	cpi	DK.LP
	mvi	a,CM.TT
	jnz	sopd1
	lda	chnew			; LP: can't be read
	cpi	CM.RD
	mvi	a,EC.DNS
	stc
	jz	sopx
	mvi	a,CM.LP
sopd1:	call	setmode
	ora	a
	jmp	sopx

sopenc:	sta	chnum
	mvi	a,1			; must not exist yet
	jmp	sopw0
sopenw:	sta	chnum
	xra	a
sopw0:	sta	chnoex
	mvi	a,CM.WR
	sta	chnew
	mov	a,b
	sta	chbc
	mov	a,c
	sta	chbc+1
	lda	chnum
	call	chopen
	jc	sopx
	cpi	DK.HDOS
	jnz	sopw2
	call	hcreate
	jmp	sopx
sopw2:	cpi	DK.DISK
	jnz	sopdev
	lda	chnoex
	ora	a
	jz	sopw1
	call	chfcb			; .OPENC: file already there?
	lxi	h,tmpfcb
	xchg
	mvi	b,FCBLEN
	call	move
	lxi	d,tmpfcb
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	mvi	a,EC.FAP
	stc
	jnz	sopx
sopw1:	call	chfcb			; write NAME.$$$
	call	tmpnam
	push	d
	mvi	c,F_DELETE
	call	BDOS
	pop	d
	mvi	c,F_MAKE
	call	BDOS
	inr	a
	mvi	a,EC.DIF
	stc
	jz	sopx
	mvi	a,CM.WR
	call	setmode
	ora	a
	jmp	sopx

; tmpnam - make the FCB at DE name NAME.$$$ (keeps DE).
tmpnam:	lxi	h,FCB.TYP
	dad	d
	mvi	m,'$'
	inx	h
	mvi	m,'$'
	inx	h
	mvi	m,'$'
	ret

; ---- .CLOSE: A = channel ----
sclose:	call	chptr
	rc
	mov	a,m
	ora	a
	mvi	a,EC.FNO
	stc
	rz
	call	chcls
	ora	a
	ret

; chcls - close channel chp (open), finishing any write.
chcls:	lhld	chp
	mov	a,m
	cpi	CM.HWR			; HDOS write or update
	jc	chc0
	call	hclose
	lhld	chp
	mvi	m,CM.CLS
	ret
chc0:	mvi	m,CM.CLS
	cpi	CM.TT
	rnc				; devices: nothing to do
	push	psw
	call	chfcb
	mvi	c,F_CLOSE
	call	BDOS
	pop	psw
	cpi	CM.WR
	rnz
	; Replace the old file: delete NAME.EXT, rename NAME.$$$ to it.
	call	chreal			; tmpfcb = NAME.EXT
	lxi	d,tmpfcb
	mvi	c,F_DELETE
	call	BDOS
	call	chfcb			; FCB+16 = new name
	lxi	h,16
	dad	d
	xchg
	lxi	h,tmpfcb
	mvi	b,16
	call	move
	call	chfcb
	lxi	h,16
	dad	d
	mvi	m,0
	mvi	c,F_RENAME
	jmp	BDOS

; chreal - tmpfcb = the channel's real file name.
chreal:	lhld	chp			; ddrv = the drive in its FCB
	inx	h
	mov	a,m
	sta	ddrv
	lxi	d,CH.DNAM-1
	dad	d
	lxi	d,dnam
	mvi	b,14
	call	move
	lxi	d,tmpfcb
	jmp	mkfcb

; ---- .CLEAR: A = channel. A write is thrown away. ----
sclear:	call	chptr
	rc
	call	chclr
	ora	a
	ret

; chclr - clear channel chp.
chclr:	lhld	chp
	mov	a,m
	cpi	CM.HWR			; HDOS write: give the groups back
	jnz	chclr1
	mvi	m,CM.CLS
	jmp	hclear
chclr1:	cpi	CM.WR
	jnz	chcls1
	mvi	m,CM.CLS		; delete NAME.$$$
	call	chfcb
	mvi	c,F_CLOSE
	call	BDOS
	call	chfcb
	mvi	c,F_DELETE
	jmp	BDOS
chcls1:	ora	a			; others: as .CLOSE
	rz
	jmp	chcls

; ---- .CLEARA: clear channels 0-5 ----
sclra:	xra	a
sca1:	push	psw
	call	chptr
	call	chclr
	pop	psw
	inr	a
	cpi	NCHAN-1
	jc	sca1
	xra	a
	ret

; clsall - at exit: .CLEARA and close channel -1.
clsall:	call	sclra
	mvi	a,-1
	call	chptr
	mvi	m,CM.CLS
	ret

; ---- .READ / .WRITE: A = channel, BC = count, DE = address. ----
; Exit BC = count left, DE = next address; CY, A = EC.* on error.

sread:	call	rwchk
	rc
	cpi	CM.TT
	jz	ttread
	cpi	CM.WR
	jz	rw.ilr
	cpi	CM.LP
	jz	rw.ilr
	cpi	CM.HWR
	jz	rw.ilr

; chrd - read B sectors into DE from open channel chp (not TT:).
chrd:	lhld	chp
	mov	a,m
	cpi	CM.HRD
	jz	hread
	cpi	CM.HUP
	jz	hread
	cpi	CM.SYN
	jz	synrd
	mvi	a,F_READRAND
	jmp	rwsec

swrite:	call	rwchk
	rc
	cpi	CM.TT
	jz	ttwrit
	cpi	CM.LP
	jz	lpwrit
	cpi	CM.RD
	jz	rw.ilr
	cpi	CM.HWR			; HDOS write, update
	jnc	hwrite
	cpi	CM.HRD			; HDOS read, made-up directory
	jnc	rw.ilr
	mvi	a,F_WRITERAND

; rwsec - move B sectors with BDOS function A (random read or write).
rwsec:	sta	rwfn
rws1:	mov	a,b
	ora	a
	rz				; done: NC
	push	b
	push	d
	call	rwrec			; first half
	jc	rws.e
	lxi	h,128
	dad	d
	xchg
	call	rwrec			; second half
	jnc	rws2
	cpi	EC.EOF			; half a sector at the end of a
	jnz	rws.e			; CP/M file: fill with zeros
	lda	rwfn
	cpi	F_READRAND
	jnz	rws.e
	mvi	b,128
	xra	a
rws1z:	stax	d
	inx	d
	dcr	b
	jnz	rws1z
rws2:	pop	d
	pop	b
	inr	d			; next 256 bytes
	dcr	b
	jmp	rws1
rws.e:	pop	d
	pop	b
	stc
	ret

; rwrec - one record at DE, record number advanced. CY, A = EC.*.
rwrec:	push	d
	mvi	c,F_DMAOFF
	call	BDOS
	call	chfcb
	push	d
	lda	rwfn
	mov	c,a
	call	BDOS
	pop	h
	pop	d
	ora	a
	jnz	rwr.e
	lxi	b,FCB.R0		; next record
	dad	b
	inr	m
	jnz	rwr.ok
	inx	h
	inr	m
rwr.ok:	xra	a
	ret
rwr.e:	mov	b,a
	lda	rwfn
	cpi	F_READRAND
	mov	a,b
	jnz	rwr.we
	cpi	1			; unwritten data or extent: end of file
	jz	rwr.eof
	cpi	4
	jz	rwr.eof
	cpi	6
	jz	rwr.eof
	mvi	a,EC.RF
	stc
	ret
rwr.eof: mvi	a,EC.EOF
	stc
	ret
rwr.we:	cpi	5			; directory full
	mvi	a,EC.DIF
	stc
	rz
	mvi	a,EC.EOM		; disk full and the rest
	stc
	ret

; rwchk - A = channel: A = its mode, chp set, BC/DE kept. CY, A =
; EC.* if bad or not open.
rwchk:	call	chptr
	rc
	mov	a,m
	ora	a
	rnz
	mvi	a,EC.FNO
	stc
	ret

rw.ilr:	mvi	a,EC.ILR
	stc
	ret

; TT: write BC bytes from DE to the console.
ttwrit:	mov	a,b
	ora	c
	rz
	ldax	d
	push	b
	push	d
	call	cout
	pop	d
	pop	b
	inx	d
	dcx	b
	jmp	ttwrit

; LP: write BC bytes from DE to the CP/M list device.
lpwrit:	mov	a,b
	ora	c
	rz
	ldax	d
	push	b
	push	d
	mov	e,a
	mvi	c,L_WRITE
	call	BDOS
	pop	d
	pop	b
	inx	d
	dcx	b
	jmp	lpwrit

; TT: read BC bytes into DE from the console, waiting for each one.
; ^D is end of file.
ttread:	mov	a,b
	ora	c
	rz
ttr1:	push	b
	push	d
	call	sscin
	pop	d
	pop	b
	jc	ttr1
	cpi	CTLD
	jz	rwr.eof
	stax	d
	inx	d
	dcx	b
	jmp	ttread

; ---- .POSIT: A = channel, BC = sector to position before ----
; Exit CY, A = EC.EOF and BC = sectors short if past the end (then at
; the end).
sposit:	call	rwchk
	rc
	cpi	CM.SYN
	jz	synpos
	cpi	CM.HRD
	jnc	hposit			; HDOS read, write, update
	cpi	CM.TT
	mvi	a,EC.DNS
	cmc
	rc
	push	b
	call	chfcb			; file size in records
	push	d
	mvi	c,F_SIZE
	call	BDOS
	pop	h
	lxi	d,FCB.R0
	dad	d
	mov	e,m
	inx	h
	mov	d,m			; DE = records
	dcx	h			; HL -> R0
	inx	d			; sectors = (records + 1) / 2
	ora	a
	mov	a,d
	rar
	mov	d,a
	mov	a,e
	rar
	mov	e,a
	pop	b
	push	h
	mov	h,b			; past the end?
	mov	l,c
	call	cmphd			; CY if BC < sectors
	pop	h
	jc	sp1
	jz	sp1
	mov	a,c			; BC = BC - sectors
	sub	e
	mov	c,a
	mov	a,b
	sbb	d
	mov	b,a
	push	b
	mov	b,d			; position at the end
	mov	c,e
	call	sp1
	pop	b
	mvi	a,EC.EOF
	stc
	ret
sp1:	mov	a,c			; record = sector * 2
	add	a
	mov	m,a
	mov	a,b
	ral
	inx	h
	mov	m,a
	inx	h
	mvi	m,0
	ora	a
	ret

; ---- .DELET: HL = name, DE = default block ----
sdelet:	call	nmtmp
	jnc	sdel1
	lda	dkres			; on an HDOS disk?
	cpi	DK.HDOS
	jz	hdelete
	stc
	ret
sdel1:	lxi	d,tmpfcb
	mvi	c,F_DELETE
	call	BDOS
	inr	a
	mvi	a,EC.FNF
	stc
	rz
	xra	a
	ret

; nmtmp - decode the disk file name at HL (default block DE) into
; tmpfcb.
nmtmp:	mov	b,d
	mov	c,e
	lxi	d,tmpfcb
	jmp	parsenm

; ---- .RENAM: HL = old name, DE = default block, BC = new name ----
srenam:	push	b
	call	nmtmp
	pop	h
	jnc	sren1
	lda	dkres			; on an HDOS disk?
	cpi	DK.HDOS
	jz	hrename
	stc
	ret
sren1:	lxi	b,zdef			; new name: no defaults, and any
	lxi	d,tmpfcb+16		; device in it is ignored
	call	decode
	rc
	lda	tmpfcb
	sta	ddrv
	lxi	d,tmpfcb+16
	call	mkfcb
	lda	dnam+3
	ora	a
	mvi	a,EC.IFN
	stc
	rz
	lxi	h,tmpfcb+16		; refuse to make a duplicate
	lxi	d,tmpfcb2
	mvi	b,16
	call	move
	lxi	d,tmpfcb2
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	mvi	a,EC.FAP
	stc
	rnz
	xra	a			; rename wants drive 0 here
	sta	tmpfcb+16
	lxi	d,tmpfcb
	mvi	c,F_RENAME
	call	BDOS
	inr	a
	mvi	a,EC.FNF
	stc
	rz
	xra	a
	ret

; ---- .DECODE: HL = name, DE = default block, BC = 19-byte block ----
; +0 device flags, +1 device (2), +3 unit, +4 name (8), +12 ext (3)
sdecod:	push	b
	mov	b,d
	mov	c,e
	call	decode
	pop	d
	rc
	push	d
	call	dkind
	pop	d
	rc
	ora	a			; flags: directory device, read,
	jz	sdc0			; write, random
	cpi	DK.HDOS
	mvi	a,DT.CHR
	jnz	sdc1
sdc0:	mvi	a,DT.DIR
sdc1:	stax	d
	inx	d
	lxi	h,dnam			; device, unit, name, ext
	mvi	b,14
	call	move
	xra	a			; project, version
	stax	d
	inx	d
	stax	d
	inx	d
	push	d			; the device table entry
	call	devfind
	xchg
	pop	h
	mov	m,e
	inx	h
	mov	m,d
	xra	a
	ret

; devfind - HL -> the device table entry for dnam's device, or 0.
devfind: lxi	h,devtab
df1:	mov	a,m
	ora	a
	jz	df.no
	lda	dnam
	cmp	m
	inx	h
	jnz	df2
	lda	dnam+1
	cmp	m
	jnz	df2
	dcx	h
	ret
df2:	lxi	d,DEVELEN-1
	dad	d
	jmp	df1
df.no:	lxi	h,0
	ret

DT.DIR	equ	0Fh		; DT.DD+DT.CR+DT.CW+DT.RN
DT.CHR	equ	16h		; DT.CR+DT.CW+DT.CH

; ---- .NAME: A = channel, DE = 6 bytes for device+unit+ext, HL = 9
; bytes for the name + 00 ----
sname:	push	h
	push	d
	call	rwchk
	pop	d
	pop	h
	rc
	push	h
	lhld	chp
	lxi	b,CH.DNAM
	dad	b
	mov	a,m			; device (2 letters)
	stax	d
	inx	h
	inx	d
	mov	a,m
	stax	d
	inx	h
	inx	d
	mov	a,m			; unit as a digit
	adi	'0'
	stax	d
	inx	h
	inx	d
	push	h
	lxi	b,8			; extension
	dad	b
	mvi	b,3
	call	move
	pop	h
	pop	d			; name
	mvi	b,8
	call	move
	xra	a
	stax	d
	ret

; ---- .SETTP: HL = new top of user memory ----
ssettp:	xchg
	lhld	S.SYSM
	dcx	h
	dcx	h
	call	cmphd			; CY if max < new
	jc	sst1
	xchg
	shld	S.USRM
	xra	a
	ret
sst1:	mvi	a,EC.NEM		; HL = the most allowed
	stc
	ret

; ---- .EXIT: A = 0 normal, 1 abort ----
sexit:	jmp	hexit

; ---- .LINK: HL = program name, DE = default block. ----
; Runs it with the stack as it was at the SCALL and A unchanged.
slink:	mov	b,d
	mov	c,e
	call	ldprog
	rc
	lxi	h,0			; no ^A/^B/^C handlers
	shld	S.CAADR
	shld	S.CCTAB
	shld	S.CCTAB+2
	shld	S.CCTAB+4
	lhld	scsp			; SP as at the SCALL
	inx	h
	inx	h
	sphl
	lhld	pentry
	push	h
	lda	sca
	ei
	jmp	TROUT

; ---- .ERROR: A = error code, H = char to print after the message ----
; The message comes from ERRORMSG.SYS (lines "NNNtext"), looked for on
; the current drive and then A:, as HDOS looks on SY0:.
serror:	sta	errc
	mov	a,h
	sta	errh
	lda	errc			; code as 3 decimal digits
	mvi	b,'0'-1
er1:	inr	b
	sui	100
	jnc	er1
	adi	100
	mov	c,a
	mov	a,b
	sta	errd
	mov	a,c
	mvi	b,'0'-1
er2:	inr	b
	sui	10
	jnc	er2
	adi	10+'0'
	sta	errd+2
	mov	a,b
	sta	errd+1

	lxi	h,errnam
	shld	ernamp
	xra	a			; current drive, then A:
	call	eropen
	jnc	er3
	mvi	a,1
	call	eropen
	jc	er.nf
er3:	; Look for a line starting with the 3 digits.
er4:	lxi	h,errd
	mvi	b,3
er5:	push	h
	push	b
	call	ergetc
	pop	b
	pop	h
	jc	er.nf
	cmp	m
	jnz	er6
	inx	h
	dcr	b
	jnz	er5
er7:	call	ergetc			; found: print the rest of the line
	jc	er.end
	cpi	NL
	jz	er.end
	call	cout
	jmp	er7
er6:	cpi	NL			; skip to the next line
	jz	er4
	call	ergetc
	jc	er.nf
	jmp	er6
er.nf:	mvi	a,BEL			; not found: "?02 Error # NNN "
	call	cout
	lxi	h,mernum
	call	coutz
	lxi	h,errd
	mvi	b,3
er.nf1:	mov	a,m
	push	h
	push	b
	call	cout
	pop	b
	pop	h
	inx	h
	dcr	b
	jnz	er.nf1
	mvi	a,' '
	call	cout
er.end:	lda	errh
	call	cout
	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS
	xra	a
	ret

; perror - print the message for error A and a new line.
perror:	mvi	h,NL
	jmp	serror

; eropen - open the file named at ernamp (ERRORMSG.SYS, HCOS.CFG) on
; drive A (0 = current). CY if absent.
eropen:	lxi	h,errfcb
	mov	m,a
	inx	h
	push	h
	lhld	ernamp
	xchg
	pop	h
	xchg
	mvi	b,11
	call	move
	xchg
	mvi	b,FCBLEN-12
	xra	a
ero1:	mov	m,a
	inx	h
	dcr	b
	jnz	ero1
	lxi	d,errfcb
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	stc
	rz
	mvi	a,128
	sta	errp
	ora	a
	ret

; ergetc - next char of ERRORMSG.SYS in A. CY at the end.
ergetc:	lda	errp
	cpi	128
	jc	erg1
	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	BDOS
	lxi	d,errfcb
	mvi	c,F_READ
	call	BDOS
	ora	a
	stc
	rnz
erg1:	mov	e,a
	inr	a
	sta	errp
	mvi	d,0
	lxi	h,TBUF
	dad	d
	mov	a,m
	ora	a			; NUL or ^Z: the end
	stc
	rz
	cpi	1Ah
	stc
	rz
	ora	a
	ret

; coutz - print the zero-terminated string at HL.
coutz:	mov	a,m
	ora	a
	rz
	push	h
	call	cout
	pop	h
	inx	h
	jmp	coutz

mernum:	db	'?02 Error # ',0
errnam:	db	'ERRORMSGSYS'
ernamp:	dw	errnam

; romprog - H-mode if HCOS.CFG (current drive, then A:) has a line
; "ROMPROG NAME" for this program.
romprog: lxi	h,cfgnam
	shld	ernamp
	xra	a
	call	eropen
	jnc	rp2
	mvi	a,1
	call	eropen
	rc
rp2:	lxi	h,mrprog		; "ROMPROG " at the start of a line
rp3:	push	h
	call	ergetc
	pop	h
	rc
	call	ucase
	cmp	m
	jnz	rp5
	inx	h
	mov	a,m
	ora	a
	jnz	rp3
	lhld	pname			; then this program's name
rp4:	mov	a,m
	cpi	' '+1
	jc	rp6
	push	h
	call	ergetc
	pop	h
	rc
	call	ucase
	cmp	m
	jnz	rp5
	inx	h
	jmp	rp4
rp6:	call	ergetc			; and nothing more on the line
	jc	rp7
	cpi	' '+1
	jnc	rp5
rp7:	mvi	a,1
	sta	hmode
	ret
rp5:	cpi	0Ah			; skip to the next line
	jz	rp2
	call	ergetc
	rc
	jmp	rp5

cfgnam:	db	'HCOS    CFG'
mrprog:	db	'ROMPROG ',0
zdef:	db	0,0,0,0,0,0

; ---- Data ----
dnam:	ds	2			; device letters
	ds	1			; unit 0-7
	ds	8			; name, zero padded
	ds	3			; extension, zero padded
dexpl:	db	0			; device given in the name
ddrv:	db	0			; FCB drive for a disk
tokb:	ds	9
tokn:	db	0
chp:	dw	0			; current channel entry
chname:	dw	0			; name pointer after decoding
chkind:	db	0
chnew:	db	0			; mode being opened
chnoex:	db	0			; .OPENC: must not exist
chnum:	db	0			; channel being opened
dkres:	db	0			; kind of disk parsenm found
chbc:	dw	0			; caller's BC (B, C)
rwfn:	db	0
errc:	db	0
errh:	db	0
errd:	ds	3
errp:	db	0
