; h37.asm - the H37 driver
;
; In the H17/H37 build booted from the H17 it sits in the BIOS's slot
; (h37com.asm assembles it there, as H37.COM, which copies it in at cold
; boot) and has drives D:-F:. Booted from the H37 it is the BIOS's own
; driver (bios.asm includes it), with A:-C:. Its entries are the same as
; every driver's (h17.asm): dkrd, dkwr, dkop, dkrdy, dktck, dkini, and
; dkisr for RST 4. Its variables are in biosram.inc. Units 0-2. (Its
; internal names start with k, so that it can be assembled with the H17
; driver, as FORMAT.COM does.) For
; now: single-sided, single-density disks, 40 tracks of 10 x 256 bytes,
; Heath's format 0 and the HDOS H37 format, the same layout as the H17.
; The physical sector of host sector n is n + 1: the interleave is in the
; sector IDs, so there is no skew here.
;
; The controller (docs/research/h37.md): a WD1797 at 7AH-7BH, the
; control latch at 78H, the interface latch at 79H. Each byte of a
; transfer ends a HALT (DRQ, answered with EI); the end of a command is
; INTRQ on RST 4, which jumps to the completion address in h37cmp with
; the status in h37st. Interrupts must be on.

DK.CON	equ	78h		; control latch (write only)
DK.INT	equ	79h		; interface latch: 1 = sector/track registers
DK.CMD	equ	7Ah		; command / status (or sector)
DK.DAT	equ	7Bh		; data (or track)
CN.INT	equ	01h		; INTRQ interrupt enable
CN.DRQ	equ	02h		; DRQ ends a HALT
CN.MO	equ	08h		; motor
CN.DS0	equ	10h		; drive select 0 (1: 20H, 2: 40H)
KRATE	equ	3		; step rate: 30 ms
FD.RES	equ	00h+KRATE	; Restore
FD.SEEK	equ	18h+KRATE	; Seek, head load
FD.RD	equ	88h		; Read Sector
FD.WR	equ	0A8h		; Write Sector
FD.FI	equ	0D0h		; Force Interrupt, no interrupt
K.MOTOR	equ	500		; ticks: motor start, 1 s
K.SELECT equ	28		; another drive, motor running: 56 ms
K.SETTLE equ	10		; after a seek: 20 ms
K.OFF	equ	15		; motor off after 15 x 512 ms
KRETRIES	equ	4

; ---- Entries ----

dkop:	ora	a		; (B.PHYS) physical sector 0-9
	lda	physec
	jnz	kwr1
	jmp	krd1
dkrd:	lda	hstsec
krd1:	inr	a		; sectors are numbered from 1
	sta	dksec
	mvi	a,FD.RD
	jmp	kop
dkwr:	lda	hstsec
kwr1:	inr	a
	sta	dksec
	mvi	a,FD.WR
kop:	sta	dkcmd
	lda	hunit
	call	kselect
	mvi	a,KRETRIES
	sta	dkrtry
kop1:	call	kseek
	jc	kop3
	call	kxfer
	jnc	kop9
kop3:	mov	b,a
	ani	0c0h		; not ready or write protect: give up
	mov	a,b
	jnz	kop8
	lxi	h,dkrtry
	dcr	m
	jz	kop8
	mov	a,m
	cpi	KRETRIES/2	; halfway: find track 0 again
	jnz	kop1
	call	ktrkptr
	mvi	m,0ffh
	jmp	kop1
kop8:	stc
kop9:	push	psw
	lda	latch		; DRQ off, the motor timer on
	out	DK.CON
	mvi	a,K.OFF
	sta	mtim37
	pop	psw
	ret

; Is unit A ready: does the index hole come by within 400 ms?
dkrdy:	call	kselect
	mvi	a,FD.FI
	out	DK.CMD
	lxi	h,200
	call	tdead
krdy1:	in	DK.CMD		; Type I status: bit 1 = index
	ani	02h
	jnz	krdy2
	call	tpast
	jc	krdy1
	mvi	a,80h
	stc
	jmp	kop9
krdy2:	xra	a
	jmp	kop9

; Every 512 ms: the motor-off timer.
dktck:	lda	mtim37
	ora	a
	rz
	dcr	a
	sta	mtim37
	rnz
	lda	latch		; motor off, nothing selected
	ani	CN.INT
	sta	latch
	out	DK.CON
	ret

; RST 4: INTRQ. Read the status (which clears it); if a command is
; waiting for it, drop what was interrupted and go to its completion.
dkisr:	push	psw
	xra	a
	out	DK.INT
	in	DK.CMD
	sta	h37st
	lda	h37act
	ora	a
	jz	kisr9
	xra	a
	sta	h37act
	pop	psw
	pop	psw		; (the HALT loop's or spin's address)
	lhld	h37cmp
	lda	h37st
	ei
	pchl
kisr9:	pop	psw
	ei
	ret

dkini:	xra	a
	sta	latch
	sta	mtim37
	out	DK.CON
	out	DK.INT
	mvi	a,FD.FI
	out	DK.CMD
	mvi	a,0ffh
	lxi	h,dktrk
	mov	m,a
	inx	h
	mov	m,a
	inx	h
	mov	m,a
	ret

; ---- Inside ----

; Select unit A and start the motor, waiting as long as they need.
kselect:	mov	b,a
	xra	a
	sta	mtim37
	mvi	a,CN.DS0
ksel1:	dcr	b
	jm	ksel2
	add	a
	jmp	ksel1
ksel2:	mov	b,a
	lda	latch
	mov	c,a
	mov	a,b
	ori	CN.MO+CN.INT
	sta	latch
	out	DK.CON
	lxi	h,K.MOTOR
	mov	a,c
	ani	CN.MO
	jz	twait		; the motor was off
	lxi	h,K.SELECT
	mov	a,c
	ani	0f0h
	cmp	b
	jnz	twait		; another drive
	ret

; HL = this unit's entry in dktrk.
ktrkptr:	lda	hunit
	lxi	h,dktrk
	add	l
	mov	l,a
	rnc
	inr	h
	ret

; Seek to hsttrk; restore first if the track is unknown. CY, A = the
; status on an error.
kseek:	call	ktrkptr
	mov	a,m
	inr	a
	jnz	ksk1
	mvi	a,FD.RES
	call	ktype1
	rc
	call	ktrkptr
	mvi	m,0
ksk1:	lda	hsttrk
	cmp	m
	rz
	mvi	a,1		; track register = where we are
	out	DK.INT
	mov	a,m
	out	DK.DAT
	xra	a
	out	DK.INT
	lda	hsttrk		; data register = where to go
	out	DK.DAT
	mvi	a,FD.SEEK
	call	ktype1
	rc
	call	ktrkptr
	lda	hsttrk
	mov	m,a
	lxi	h,K.SETTLE
	call	twait
	ora	a
	ret

; A Type I command: issue it and wait for INTRQ. CY on a seek error.
ktype1:	lxi	h,kt1done
	shld	h37cmp
	mvi	h,1
	mov	l,a
	mov	a,h
	sta	h37act
	mov	a,l
	out	DK.CMD
	ei
	jmp	$		; INTRQ goes to kt1done
kt1done:	ani	90h		; not ready, seek error
	rz
	stc
	ret

; Read or write (dkcmd) sector dksec of the track under the head, with
; hstbuf. CY, A = the status bits on an error.
kxfer:	mvi	a,1
	out	DK.INT
	lda	dksec
	out	DK.CMD		; sector register
	xra	a
	out	DK.INT
	lxi	h,kxdone
	shld	h37cmp
	mvi	a,1
	sta	h37act
	lda	latch
	ori	CN.DRQ
	out	DK.CON
	lxi	d,hstbuf
	lda	dkcmd
	cpi	FD.WR
	lxi	h,kwloop
	jz	kxf1
	lxi	h,krloop
kxf1:	out	DK.CMD
	ei
	pchl
krloop:	hlt			; DRQ ends it
	in	DK.DAT
	stax	d
	inx	d
	pchl
kwloop:	ldax	d
	hlt
	out	DK.DAT
	inx	d
	pchl
kxdone:	mov	b,a		; INTRQ: the command is over
	lda	latch
	out	DK.CON
	mov	a,b
	ani	0dch		; not ready, WP, not found, CRC, lost
	rz
	stc
	ret

h37cend:			; (the end of its code)
