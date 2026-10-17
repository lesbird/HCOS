; h37boot.asm - HCOS v2 boot record for the H37 (sector 1, track 0)
;
; MTR-90 reads all of track 0 (10 x 256 bytes, single density) to 2280H
; and jumps here with the ROM in, interrupts on, the boot unit in 2131H
; and its INTRQ handler on RST 4 (2028H: it reads the status into A and
; jumps to the address in 2037H). Track 0 is the first 2560 bytes of the
; reserved tracks: copy them to SYSB, read tracks 1 and 2 after them with
; the 1797, and start the BIOS's cold boot with interrupts off and the
; ROM still in. Each byte ends a HALT (DRQ); the card holds off the clock
; while DRQ is on, so the ROM's clock never sees the HALT.
; (docs/research/boot.md, h37.md)

	.8080
	include	layout.inc

DK.CON	equ	78h		; control latch
DK.INT	equ	79h		; 1 = sector/track registers at 7AH/7BH
DK.CMD	equ	7Ah
DK.DAT	equ	7Bh
BUNIT	equ	2131h		; the boot unit
INTRET	equ	2037h		; where the ROM's INTRQ handler goes
.DLY	equ	002Bh		; the ROM's: wait A ticks

	org	BOOTB

	jmp	start
	ds	1Ah		; 03H-1CH: the disk's label (kept by mksys.py)

start:	lxi	h,BOOTB		; track 0, here already
	lxi	d,SYSB
	lxi	b,0A00h
cp1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	cp1
	lda	BUNIT		; the latch: the unit, motor, INTRQ
	mov	b,a
	mvi	a,10h
bu1:	dcr	b
	jm	bu2
	add	a
	jmp	bu1
bu2:	ori	09h
	sta	blatch
	out	DK.CON
	mvi	a,1		; then tracks 1 and 2, to DE
trk:	sta	btrk
	xra	a		; seek: the data register = the track
	out	DK.INT
	lda	btrk
	out	DK.DAT
	lxi	h,sdone
	shld	INTRET
	mvi	a,1Bh		; Seek, head load, 30 ms steps
	out	DK.CMD
	ei
	jmp	$		; INTRQ goes to sdone
sdone:	mvi	a,10		; settle, 20 ms
	call	.DLY
	mvi	c,1
sec:	mvi	b,4		; tries
sec1:	push	d
	mvi	a,1		; the sector register
	out	DK.INT
	mov	a,c
	out	DK.CMD
	xra	a
	out	DK.INT
	lxi	h,rdone
	shld	INTRET
	lda	blatch		; DRQ on
	ori	02h
	out	DK.CON
	lxi	h,rloop
	mvi	a,88h		; Read Sector
	out	DK.CMD
	ei
rloop:	hlt
	in	DK.DAT
	stax	d
	inx	d
	pchl
rdone:	mov	h,a		; INTRQ: A = the status
	lda	blatch		; DRQ off
	out	DK.CON
	mov	a,h
	ani	9Ch		; not ready, not found, CRC, lost data
	jz	sec2
	pop	d		; again, into the same place
	dcr	b
	jnz	sec1
	jmp	error
sec2:	pop	h		; (DE is past it now)
	inr	c
	mov	a,c
	cpi	11
	jc	sec
	lda	btrk
	inr	a
	cpi	3
	jc	trk
	mvi	a,08h		; motor only, nothing selected
	out	DK.CON
	di
	jmp	B.BOOT

error:	lxi	h,emsg
eloop:	in	CON.LSR
	ani	20h
	jz	eloop
	mov	a,m
	ora	a
	jz	0		; back to the monitor
	out	CON
	inx	h
	jmp	eloop

emsg:	db	0dh,0ah,'?HCOS boot error',0dh,0ah,0
blatch:	db	0
btrk:	db	0

	assert	$ <= BOOTB+0F8h	; (SYSTAB follows)
