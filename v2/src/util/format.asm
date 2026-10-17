; format.asm - FORMAT.COM: format a disk for CP/M or HDOS
;
;	FORMAT d:	a CP/M disk (empty directory)
;	FORMAT d: HDOS	an HDOS 2.0 data disk, as HDOS INIT makes one
;
; Single-sided, single-density, 40 tracks of 10 x 256 bytes, on an H17 or
; an H37 drive (D:-F: are the second controller's in the H17/H37 builds).
; Not A:. It asks first. Each track is read back and checked.
;
; FORMAT drives the controller itself, with the BIOS's own driver code
; (h17.asm, h37.asm), assembled in for this build so that its variables
; are the BIOS's (biosram.inc): the BIOS's RST 4 handler then completes
; the H37's commands, and its clock leaves the motors alone while FORMAT
; has them. (docs/research/fmt-h17.md, fmt-h37.md, hdosinit.md)

	include	util.inc
	include	biosram.inc

FILL	equ	0E5h		; data: E5H, CP/M's empty directory
TRK37	equ	3000h		; the H37 track image, 3.3K
HDOSB	equ	4000h		; the HDOS structures (below)

main:	lda	DFCB		; d:, not A:
	dcr	a
	jm	usage
	jz	usage
	cpi	NDRIVE
	jnc	usage
	sta	drv
	lda	DFCB+16+1	; HDOS?
	cpi	'H'
	jnz	mn1
	sta	hdos
mn1:	lda	drv		; which controller, which unit
	mov	c,a
	cpi	3
	mvi	b,0		; B = 1 for the second controller
	jc	mn2
	sui	3
	inr	b
mn2:	sta	unit
	mov	a,b		; the boot controller's is the H17,
	xri	1		; unless this build boots from the H37
	if	CORE37
	xri	1
	endif
	sta	is17		; (1 = H17, 0 = H37)
	call	drvok
	jz	nodrv
	jc	notrdy
	lxi	d,mask1		; "Format d: (H17 1) for CP/M? ... "
	call	pstr
	lda	drv
	adi	'A'
	call	pch
	lxi	d,mask2
	call	pstr
	lxi	d,mh37
	lda	is17
	ora	a
	jz	mn3
	lxi	d,mh17
mn3:	call	pstr
	lda	unit
	adi	'0'
	call	pch
	lxi	d,mcpm
	lda	hdos
	ora	a
	jz	mn4
	lxi	d,mhdos
mn4:	call	pstr
	lxi	d,mask3
	call	pstr
	mvi	c,C_READ
	call	BDOS
	ani	5Fh
	cpi	'Y'
	jnz	BOOT
	call	crlf
	xra	a		; the BIOS's host buffer is ours now
	sta	hstact
	sta	hstwrt
	lda	hdos
	ora	a
	cnz	hdprep		; serial, date (through the BDOS)
	lda	unit		; (after the BDOS: its reads set hunit)
	sta	hunit
	lda	is17
	ora	a
	jz	mn5
	call	fmt17
	jmp	mn6
mn5:
	if	SLOTS
	call	fmt37
	else
	stc
	endif
mn6:	jc	fmterr
	lda	hdos
	ora	a
	jz	mn7
	call	hdinit		; the HDOS label, RGT, GRT, directory
	jc	wrerr
	jmp	done
mn7:	lda	is17		; CP/M on the H37: Heath's label
	ora	a
	if	SLOTS
	cz	lab37
	jc	wrerr
	endif
done:	lxi	d,mdone
	call	pstr
	jmp	BOOT

usage:	lxi	d,musage
	jmp	fail
nodrv:	lxi	d,mnodrv
	jmp	fail
notrdy:	lxi	d,mnotr
	jmp	fail
wrerr:	lxi	d,mwr
	jmp	fail
fmterr:	lxi	d,mbad
	call	pstr
	lda	hsttrk
	mov	l,a
	mvi	h,0
	call	pdec
	call	crlf
	jmp	BOOT
fail:	call	pstr
	jmp	BOOT

; Print HL (0-99) in decimal.
pdec:	mov	a,l
	mvi	b,'0'-1
pd1:	inr	b
	sui	10
	jnc	pd1
	adi	'0'+10
	push	psw
	mov	a,b
	call	pch
	pop	psw
	jmp	pch

; ---- The H17 ----

; fmt17 - format unit hunit: 40 tracks, then read each one back. CY on
; an error (hsttrk = the track).
fmt17:	lda	hunit
	call	select		; (stops the BIOS's motor timer)
	in	DP.CTL
	ani	DF.WP
	stc
	jnz	f17x
	call	trkptr		; find track 0
	mvi	m,0ffh
	xra	a
	sta	hsttrk
	call	seek
	jc	f17x
	xra	a		; the fill character
	out	DP.DATA+1
f17t:	call	seek
	jc	f17x
	lxi	h,35		; settle, 70 ms
	call	twait
	lda	hsttrk		; the volume: 0 on track 0
	ora	a
	jz	f17v
	lda	vol
f17v:	sta	hvol
	call	trk17
	jc	f17x
	mvi	a,0		; read it back
f17r:	sta	physec
	xra	a
	call	h17op
	jc	f17x
	call	chkfill
	jc	f17x
	lda	physec
	inr	a
	cpi	10
	jc	f17r
	lda	hsttrk
	inr	a
	sta	hsttrk
	cpi	40
	jc	f17t
	ora	a
f17x:	push	psw
	mvi	a,T.OFF		; the motor timer again
	sta	mtim
	pop	psw
	ei
	ret

; trk17 - write track hsttrk: erase it with the gate on for 250 ms, find
; the index hole by the gaps between holes (10 ms around the index, 20 ms
; between sectors), then each sector after its hole as Heath's FORMAT
; does: 10 x 00, FD, volume, track, sector, checksum, 00, 10 x 00, FD,
; 256 x FILL, checksum, 00, 00. CY if the holes don't come.
trk17:	lda	s7f
	ori	DF.WG
	out	DP.CTL
	lxi	h,125
	call	twait
	call	hedge
	rc
tk1:	lhld	tickc		; a long gap first
	shld	t0
	call	hedge
	rc
	call	gap
	jc	tk1
tk2:	lhld	tickc		; then the short one into the index
	shld	t0
	call	hedge
	rc
	call	gap
	jnc	tk2
	call	hend		; the index hole is passing
	rc
	mvi	c,0
tk3:	di
	call	hedgdi
	jc	tk9
	mvi	a,20		; 280 T
tk4:	dcr	a
	jnz	tk4
	lda	s7f
	ori	DF.WG
	out	DP.CTL
	mvi	b,10
	call	zeros
	mvi	a,0fdh
	call	wnb
	mvi	d,0
	lda	hvol
	call	fwnb
	lda	hsttrk
	call	fwnb
	mov	a,c
	call	fwnb
	mov	a,d
	call	wnb
	xra	a
	call	wnb
	mvi	b,10
	call	zeros
	mvi	a,0fdh
	call	wnb
	mvi	d,0
	mvi	b,0
tk5:	in	DP.STAT		; 256 x FILL
	ora	a
	jp	tk5
	mvi	a,FILL
	out	DP.DATA
	xra	d
	rlc
	mov	d,a
	dcr	b
	jnz	tk5
	mov	a,d
	call	wnb
	xra	a
	call	wnb
	xra	a
	call	wnb
	lda	s7f		; gate off
	out	DP.CTL
	ei
	inr	c
	mov	a,c
	cpi	10
	jc	tk3
	ora	a
	ret
tk9:	lda	s7f
	out	DP.CTL
	ei
	stc
	ret

; NC if the gap since t0 was a long one (6 ticks or more), CY if short.
gap:	lhld	t0
	xchg
	lhld	tickc
	mov	a,l
	sub	e
	cpi	6		; (CY: a short one)
	ret

zeros:	xra	a
	call	wnb
	dcr	b
	jnz	zeros
	ret

; fwnb - write A, adding it to the checksum in D.
fwnb:	push	psw
	call	wnb
	pop	psw
	xra	d
	rlc
	mov	d,a
	ret

; hend - wait for the hole showing to end; hedge - then for the next
; hole's leading edge. With interrupts on; CY after 100 ms.
hend:	lxi	h,50
	call	tdead
he1:	in	DP.CTL
	rar
	rnc
	call	tpast
	jc	he1
	stc
	ret
hedge:	call	hend
	rc
	lxi	h,50
	call	tdead
hg1:	in	DP.CTL
	rar
	cmc
	rnc
	call	tpast
	jc	hg1
	stc
	ret

; hedgdi - the same, with interrupts off: a hole's leading edge within
; about 30 ms. CY if none.
hedgdi:	lxi	h,1200
hd1:	in	DP.CTL		; out of the hole first
	rar
	jnc	hd2
	dcx	h
	mov	a,h
	ora	l
	jnz	hd1
	stc
	ret
hd2:	in	DP.CTL
	rar
	jc	hd3		; the edge
	dcx	h
	mov	a,h
	ora	l
	jnz	hd2
	stc
	ret
hd3:	ora	a		; NC
	ret

; chkfill - CY unless hstbuf is all FILL.
chkfill: lxi	h,hstbuf
	mvi	b,0
cf1:	mov	a,m
	cpi	FILL
	stc
	rnz
	inx	h
	dcr	b
	jnz	cf1
	ora	a
	ret

	if	SLOTS
; ---- The H37 ----

; fmt37 - format unit hunit: build the track (Heath's FM stream,
; interleave 3), then for each track seek, write it with Write Track and
; read each sector back. CY on an error (hsttrk = the track).
fmt37:	call	bld37
	lda	hunit
	call	kselect		; (stops the BIOS's motor timer)
	call	ktrkptr		; find track 0
	mvi	m,0ffh
	xra	a
	sta	hsttrk
f37t:	call	kseek
	jc	f37x
	lxi	h,idps		; C in each ID
	mvi	b,10
f37c:	mov	e,m
	inx	h
	mov	d,m
	inx	h
	lda	hsttrk
	stax	d
	dcr	b
	jnz	f37c
	call	wtrk
	jc	f37x
	lxi	h,ilv		; read it back, in the order on the disk
f37r:	mov	a,m
	ora	a
	jz	f37n
	push	h
	sta	dksec
	mvi	a,FD.RD
	sta	dkcmd
	call	kxfer
	cnc	chkfill
	pop	h
	jc	f37x
	inx	h
	jmp	f37r
f37n:	lda	hsttrk
	inr	a
	sta	hsttrk
	cpi	40
	jc	f37t
	ora	a
f37x:	push	psw
	lda	latch		; DRQ off; the motor timer again
	out	DK.CON
	mvi	a,K.OFF
	sta	mtim37
	pop	psw
	ret

; wtrk - Write Track from TRK37: each byte ends a HALT (DRQ); INTRQ
; comes to wtdone (the BIOS's RST 4 handler) with the status. The 1797
; takes one turn, so DE must end between 3070 and 3302 bytes in.
wtrk:	lxi	h,wtdone
	shld	h37cmp
	mvi	a,1
	sta	h37act
	lda	latch
	ori	CN.DRQ
	out	DK.CON
	lxi	d,TRK37
	lxi	h,wtloop
	mvi	a,0F4h		; Write Track
	out	DK.CMD
	ei
wtloop:	ldax	d
	hlt
	out	DK.DAT
	inx	d
	pchl
wtdone:	mov	b,a
	lda	latch
	out	DK.CON
	mov	a,b
	ani	0C4h		; not ready, write protect, lost data
	stc
	rnz
	lxi	h,-(TRK37+3070)	; the speed
	dad	d
	cmc
	ret

; bld37 - the FM track image: 16 x FF, then for each sector 6 x 00, FE,
; C H R N (C filled in per track), F7, 11 x FF, 6 x 00, FB, 256 x FILL,
; F7, 16 x FF; then FF to the end. idps -> each sector's C.
bld37:	lxi	h,TRK37
	mvi	a,0ffh
	mvi	b,16
	call	fillb
	lxi	d,ilv
	lxi	b,idps
bl1:	ldax	d
	ora	a
	jz	bl2
	push	d
	push	b
	push	psw
	mvi	b,6
	xra	a
	call	fillb
	mvi	m,0feh
	inx	h
	pop	psw
	pop	b
	push	psw		; idps[n] = here
	mov	a,l
	stax	b
	inx	b
	mov	a,h
	stax	b
	inx	b
	pop	psw
	mvi	m,0		; C
	inx	h
	mvi	m,0		; H
	inx	h
	mov	m,a		; R
	inx	h
	mvi	m,1		; N: 256
	inx	h
	mvi	m,0f7h
	inx	h
	push	b
	mvi	b,11
	mvi	a,0ffh
	call	fillb
	mvi	b,6
	xra	a
	call	fillb
	mvi	m,0fbh
	inx	h
	mvi	b,0
	mvi	a,FILL
	call	fillb
	mvi	m,0f7h
	inx	h
	mvi	b,16
	mvi	a,0ffh
	call	fillb
	pop	b
	pop	d
	inx	d
	jmp	bl1
bl2:	lxi	b,256		; 256 more FF: past the end of the turn
bl3:	mvi	m,0ffh
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	bl3
	ret

; The sector IDs in the order on the disk: interleave 3, as Heath's.
ilv:	db	1,8,5,2,9,6,3,10,7,4,0
idps:	ds	20

; lab37 - Heath's label, in sector 1 of track 0 (as Heath's FORMAT
; writes it for format 0): its BIOS reads the format there.
lab37:	lxi	h,hstbuf
	mvi	b,0
	mvi	a,FILL
	call	fillb
	lxi	h,lab0
	lxi	d,hstbuf+4
	mvi	b,LAB0N
lb1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	lb1
	lxi	h,hstbuf+4	; the check byte: sum(04H-1CH) + 1 = 0
	mvi	b,1Ch-4
	xra	a
lb2:	add	m
	inx	h
	dcr	b
	jnz	lb2
	cma
	mov	m,a
	xra	a
	sta	hsttrk
	sta	physec
	mvi	a,1
	jmp	dkop
lab0:	db	00h,60h,0E5h,02h,08h,0E5h,0E5h,00h,0E5h
	dw	20		; the DPB: SPT
	db	3,7,0		; BSH, BLM, EXM
	dw	91,63		; DSM, DRM
	db	0C0h,0		; AL0, AL1
	dw	16,3		; CKS, OFF
LAB0N	equ	$-lab0
	endif

; ---- HDOS ----
; The disk as HDOS INIT makes it (docs/research/hdosinit.md): 2 sectors
; a group, 200 groups. Groups 0-4 (track 0) reserved, RGT.SYS in group 5
; (sector 10), DIRECT.SYS in 9 groups and GRT.SYS in group 74 (sector
; 148). The label is sector 9.

SPG	equ	2
NGRP	equ	200
GRTG	equ	74
RGTS	equ	10

; hdprep - the volume serial (from the clock, 1-255) and the date (from
; A:HDOS.COM's date block, if it is there).
hdprep:	lhld	tickc
	mov	a,l
	ora	a
	jnz	hp1
	inr	a
hp1:	sta	vol
	lxi	d,hdfcb
	mvi	c,F_OPEN
	call	BDOS
	inr	a
	rz
	lxi	d,HDOSB
	mvi	c,F_DMAOFF
	call	BDOS
	lxi	d,hdfcb
	mvi	c,F_READ
	call	BDOS
	ora	a
	rnz
	lda	HDOSB+3
	cpi	'H'
	rnz
	lhld	HDOSB+16
	shld	date
	ret

; hdinit - write sectors 0-10, the GRT and the directory. CY on an
; error.
hdinit:	lxi	h,HDOSB		; sector 0: a stub that says so
	lxi	b,256
	call	zfill
	lxi	h,stub
	lxi	d,HDOSB
	mvi	b,STUBN
	call	copyb
	lxi	h,0
	call	wsec
	rc
	lxi	h,HDOSB		; 1-8: zeros
	lxi	b,256
	call	zfill
	lxi	h,1
hi1:	push	h
	call	wsec
	pop	h
	rc
	inx	h
	mov	a,l
	cpi	9
	jc	hi1
	call	mklab		; 9: the label
	lxi	h,9
	call	wsec
	rc
	call	mkrgt		; 10: the RGT
	lxi	h,RGTS
	call	wsec
	rc
	call	mkgrt		; 148: the GRT
	lxi	h,GRTG*SPG
	call	wsec
	rc
	xra	a		; the directory, block by block
	sta	blk
hi2:	call	mkblk
	lhld	cursec
	push	h
	call	wsec
	pop	h
	rc
	inx	h
	push	h
	lxi	h,HDOSB+256
	lxi	d,HDOSB
	lxi	b,256
	call	copyw
	pop	h
	call	wsec
	rc
	lxi	h,blk
	inr	m
	mov	a,m
	cpi	9
	jc	hi2
	ora	a
	ret

; The directory's groups in chain order: the driver's interleave (H17:
; 1,3,0,2,4,6,8,5,7 from group 65; H37: 65 on).
dg17:	db	66,68,65,67,69,71,73,70,72
dg37:	db	65,66,67,68,69,70,71,72,73

; dgrp - A = directory block A's group.
dgrp:	lxi	h,dg17
	push	psw
	lda	is17
	ora	a
	jnz	dgr1
	lxi	h,dg37
dgr1:	pop	psw
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	mov	a,m
	ret

; mklab - the label in HDOSB.
mklab:	lxi	h,HDOSB
	lxi	b,256
	call	zfill
	lda	vol
	sta	HDOSB+00h	; LAB.SER
	lhld	date
	shld	HDOSB+01h	; LAB.IND
	xra	a
	call	dgrp
	add	a		; x SPG
	mov	l,a
	mvi	h,0
	shld	HDOSB+03h	; LAB.DIS
	lxi	h,GRTG*SPG
	shld	HDOSB+05h	; LAB.GRT
	mvi	a,SPG
	sta	HDOSB+07h	; LAB.SPG
	mvi	a,20h
	sta	HDOSB+09h	; LAB.VER: 2.0 (LAB.VLT 0: data)
	lxi	h,RGTS
	shld	HDOSB+0Ah	; LAB.RGT
	lxi	h,400
	shld	HDOSB+0Ch	; LAB.SIZ
	lxi	h,256
	shld	HDOSB+0Eh	; LAB.PSS
	lxi	h,HDOSB+11h	; LAB.LAB: 61 bytes, blank-filled
	mvi	b,61
	mvi	a,' '
	call	fillb
	lxi	h,ltext
	lxi	d,HDOSB+11h
	mvi	b,LTEXTN
	call	copyb
	mvi	a,10
	sta	HDOSB+4Fh	; LAB.SPT
	ret

; mkrgt - the RGT in HDOSB: 00 00 FF FF FF, 01 for groups 5-199, FF on.
mkrgt:	lxi	h,HDOSB
	mvi	m,0
	inx	h
	mvi	m,0
	inx	h
	mvi	a,0ffh
	mvi	b,3
	call	fillb
	mvi	a,1
	mvi	b,NGRP-5
	call	fillb
	mvi	a,0ffh
	mvi	b,256-NGRP
	jmp	fillb

; mkgrt - the GRT in HDOSB: the RGT, with RGT.SYS's and GRT.SYS's groups
; ending their chains, the directory's chained, and the rest (01) in the
; free chain, ascending, its head in GRT[0].
mkgrt:	call	mkrgt
	xra	a
	sta	HDOSB+5
	sta	HDOSB+GRTG
	mvi	c,0		; the directory chain
mg1:	mov	a,c
	call	dgrp
	mov	e,a
	mvi	d,0
	lxi	h,HDOSB
	dad	d		; HL -> GRT[this]
	inr	c
	mov	a,c
	cpi	9
	mvi	a,0
	jz	mg2		; the last: 00
	mov	a,c
	push	h
	call	dgrp
	pop	h
mg2:	mov	m,a
	mov	a,c
	cpi	9
	jc	mg1
	lxi	d,HDOSB		; the free chain: DE -> the last link
	mvi	c,1
mg3:	mov	l,c
	mvi	h,HDOSB shr 8
	mov	a,m
	cpi	1
	jnz	mg4
	mov	a,c		; free: link it
	stax	d
	xchg
mg4:	inr	c
	mov	a,c
	cpi	NGRP
	jc	mg3
	xra	a		; the end
	stax	d
	ret

; mkblk - directory block blk (512 bytes) in HDOSB, and cursec = its
; first sector.
mkblk:	lda	blk
	call	dgrp
	add	a
	mov	l,a
	mvi	h,0
	shld	cursec
	lxi	h,HDOSB		; 22 empty entries: FF (block 0, 1) or FE
	mvi	c,22
	lda	blk
	cpi	2
	mvi	a,0ffh
	jc	mb1
	mvi	a,0feh
mb1:	push	psw
	mov	m,a
	inx	h
	mvi	b,22
	xra	a
	call	fillb
	pop	psw
	dcr	c
	jnz	mb1
	lda	blk		; block 1: RGT.SYS, GRT.SYS, DIRECT.SYS
	cpi	1
	jnz	mb2
	lxi	h,ent0
	lxi	d,HDOSB+18*23
	mvi	b,3*23
	call	copyb
	mvi	a,0feh		; and the end of the directory
	sta	HDOSB+21*23
	lhld	date
	shld	HDOSB+18*23+13h
	shld	HDOSB+18*23+15h
	shld	HDOSB+19*23+13h
	shld	HDOSB+19*23+15h
	shld	HDOSB+20*23+13h
	shld	HDOSB+20*23+15h
	xra	a		; DIRECT.SYS's first and last groups
	call	dgrp
	sta	HDOSB+20*23+10h
	mvi	a,8
	call	dgrp
	sta	HDOSB+20*23+11h
mb2:	xra	a		; the block's tail
	sta	HDOSB+1FAh
	mvi	a,23
	sta	HDOSB+1FBh	; DIS.ENL
	lhld	cursec
	shld	HDOSB+1FCh	; DIS.SEC
	lxi	h,0
	lda	blk
	cpi	8
	jnc	mb3
	inr	a
	call	dgrp
	add	a
	mov	l,a
	mvi	h,0
mb3:	shld	HDOSB+1FEh	; DIS.LNK
	ret

; The three system files' entries (dates filled in).
ent0:	db	'RGT',0,0,0,0,0,'SYS',0,0,0,0F0h,0,5,5,1,0,0,0,0
	db	'GRT',0,0,0,0,0,'SYS',0,0,0,0F0h,0,GRTG,GRTG,1,0,0,0,0
	db	'DIRECT',0,0,'SYS',0,0,0,0E0h,0,0,0,SPG,0,0,0,0

; wsec - write HDOSB (256 bytes) as HDOS sector HL. CY on an error.
wsec:	push	h		; track = HL / 10, sector = HL mod 10
	mvi	b,0
wsc1:	mov	a,l
	sui	10
	mov	l,a
	mov	a,h
	sbi	0
	mov	h,a
	jc	wsc2
	inr	b
	jmp	wsc1
wsc2:	mov	a,l
	adi	10
	sta	physec
	mov	a,b
	sta	hsttrk
	lxi	h,HDOSB
	lxi	d,hstbuf
	lxi	b,256
	call	copyw
	pop	h
	lda	is17
	ora	a
	mvi	a,1
	jnz	h17op
	if	SLOTS
	jmp	dkop
	else
	stc
	ret
	endif

fillb:	mov	m,a		; B bytes of A at HL
	inx	h
	dcr	b
	jnz	fillb
	ret
zfill:	mvi	m,0
	inx	h
	dcx	b
	mov	a,b
	ora	c
	jnz	zfill
	ret
copyb:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	copyb
	ret
copyw:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	copyw
	ret

; Sector 0 of an HDOS data disk: if it's booted, say so.
stub:
	.phase	BOOTB
	lxi	h,stubm
st1:	in	0EDh		; the console 8250: LSR, THRE
	ani	20h
	jz	st1
	mov	a,m
	ora	a
	jz	0
	out	0E8h
	inx	h
	jmp	st1
stubm:	db	13,10,'?Not a system disk (HCOS FORMAT)',13,10,0
	.dephase
STUBN	equ	$-stub

ltext:	db	'HCOS FORMAT'
LTEXTN	equ	$-ltext

; ---- The BIOS's clock deadlines, for the driver code ----
tdead:	xchg
	lhld	tickc
	dad	d
	shld	tdl
	ret
tpast:	lhld	tdl
	xchg
	lhld	tickc
	mov	a,l
	sub	e
	mov	a,h
	sbb	d
	ral
	ret
twait:	call	tdead
tw1:	call	tpast
	jc	tw1
	ret

	include	h17.asm
	if	SLOTS
	include	h37.asm
	endif

musage:	db	'FORMAT d: [HDOS] - format the disk in d: (not A:) for CP/M,'
	db	' or HDOS',13,10,'$'
mnodrv:	db	'FORMAT: no such drive',13,10,'$'
mnotr:	db	'FORMAT: drive not ready',13,10,'$'
mwr:	db	'FORMAT: write error',13,10,'$'
mbad:	db	'FORMAT: bad track $'
mdone:	db	'Formatted.',13,10,'$'
mask1:	db	'Format $'
mask2:	db	': ($'
mh17:	db	'H17 $'
mh37:	db	'H37 $'
mcpm:	db	') for CP/M$'
mhdos:	db	') for HDOS$'
mask3:	db	'? Everything on it will be lost (Y/N) $'
hdfcb:	db	1,'HDOS    COM',0,0,0,0
	ds	20

drv:	db	0
unit:	db	0
is17:	db	0
hdos:	db	0
vol:	db	0
hvol:	db	0
date:	dw	0
t0:	dw	0
blk:	db	0
cursec:	dw	0
