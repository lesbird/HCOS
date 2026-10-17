; h17.asm - the H17 driver, part of bios.asm
;
; h17rd / h17wr: read or write host sector hstsec (0-9, before skew) of
; track hsttrk on drive hstdsk (0-2), to or from hstbuf. h17rdp reads
; physical sector physec instead. NC on success.
; CY and A = error code on failure, after the retries:
;   01H wrong track   02H no header sync   04H header checksum
;   08H data checksum 10H sector not found 20H no data sync
;   40H write protect 80H not ready (no holes)
;
; The method is the H17 ROM's (docs/research/h17.md), in code of HCOS's
; own: wait for a sector hole (not the index hole), arm the sync search,
; check the header, then read or write the data. The volume byte in the
; header is ignored, so HDOS disks work too. Interrupts are off from the
; header sync to the end of the data: each byte has 128 T-states, and
; the inline loops below take about 75. All other state is in BIOS RAM.

DP.DATA	equ	7Ch		; USRT data
DP.STAT	equ	7Dh		; USRT status: bit 0 data available, bit 7 TBE
DP.SYNC	equ	7Eh		; out: sync character, in: start the sync search
DP.CTL	equ	7Fh		; out: control, in: status
DF.HOLE	equ	01h		; in: hole showing
DF.T0	equ	02h		; in: head on track 0
DF.WP	equ	04h		; in: write protect
DF.SD	equ	08h		; in: sync detected
DF.WG	equ	01h		; out: write gate
DF.MO	equ	10h		; out: motor
DF.DIN	equ	20h		; out: step direction in
DF.STEP	equ	40h		; out: step pulse

T.STEP	equ	15		; ticks (2 ms) after each step: 30 ms
T.SETTLE equ	12		; after the last step: 24 ms
T.MOTOR	equ	500		; motor start: 1 s
T.SELECT equ	40		; another drive, motor running: 80 ms
T.OFF	equ	15		; motor off after 15 x 512 ms (about 8 s)
RETRIES	equ	10

h17rd:	call	toskew
h17rdp:	xra	a
	jmp	h17op
h17wr:	call	toskew
	mvi	a,1
h17op:	sta	h17w
	lda	hstdsk
	call	select
	mvi	a,RETRIES
	sta	retry
hop1:	call	seek
	jc	hfatal
	lda	h17w
	ora	a
	jz	hop2
	in	DP.CTL
	ani	DF.WP
	mvi	a,40h
	jnz	hfatal
	call	findhdr
	cnc	wrdata
	jmp	hop3
hop2:	call	findhdr
	cnc	rddata
hop3:	ei
	jnc	hdone
	cpi	80h		; not ready: no use retrying
	jz	hfatal
	lxi	h,retry
	dcr	m
	jz	hfatal
	cpi	01h		; wrong track: find track 0 again
	jz	hrest
	mov	a,m
	cpi	RETRIES/2	; halfway: find track 0 again anyway
	jnz	hop1
hrest:	call	trkptr
	mvi	m,0ffh
	jmp	hop1
hfatal:	stc
hdone:	push	psw
	mvi	a,T.OFF
	sta	mtim
	pop	psw
	ei
	ret

; h17rdy: NC if drive A (0-2) is ready: a hole comes by within a turn
; and a half after the motor is up to speed.
h17rdy:	call	select
	lxi	h,150
	call	tdead
rdy1:	in	DP.CTL
	rar
	jc	rdy2
	call	tpast
	jc	rdy1
rdy2:	cmc
	push	psw
	mvi	a,T.OFF
	sta	mtim
	pop	psw
	ret

; Select drive A and start the motor, waiting as long as they need.
; Stops the motor-off timer.
select:	mov	b,a
	xra	a
	sta	mtim
	mvi	a,02h		; DS0, DS1, DS2
sel1:	dcr	b
	jm	sel2
	add	a
	jmp	sel1
sel2:	mov	b,a
	lda	s7f
	mov	c,a
	ani	0e1h		; drop the old drive and the motor
	ora	b
	ori	DF.MO
	sta	s7f
	out	DP.CTL
	lxi	h,T.MOTOR
	mov	a,c
	ani	DF.MO
	jz	twait		; the motor was off
	lxi	h,T.SELECT
	mov	a,c
	ani	0eh
	cmp	b
	jnz	twait		; another drive
	ret

; Step to hsttrk. A track of FFH is unknown: find track 0 first.
seek:	call	trkptr
	mov	a,m
	inr	a
	jnz	sk2
	mvi	b,50		; at most 50 steps out
sk1:	in	DP.CTL
	ani	DF.T0
	jnz	sk1a
	xra	a
	call	step
	dcr	b
	jnz	sk1
	mvi	a,01h		; no track 0
	stc
	ret
sk1a:	call	trkptr
	mvi	m,0
sk2:	mvi	c,0		; no steps yet
sk3:	lda	hsttrk
	cmp	m
	jz	sk5
	mvi	a,DF.DIN
	jnc	sk4		; hsttrk > track: in
	xra	a
	dcr	m
	dcr	m
sk4:	inr	m
	call	step
	inr	c
	jmp	sk3
sk5:	mov	a,c
	ora	a
	rz
	push	h
	lxi	h,T.SETTLE
	call	twait
	pop	h
	ret

; One step, direction bit in A, then wait. Keeps HL, BC.
step:	push	h
	mov	h,a
	lda	s7f
	ora	h
	out	DP.CTL
	ori	DF.STEP
	out	DP.CTL
	xri	DF.STEP
	out	DP.CTL
	lxi	h,T.STEP
	call	twait
	pop	h
	ret

; HL = this drive's entry in h17trk.
trkptr:	lda	hstdsk
	mov	l,a
	mvi	h,0
	lxi	d,h17trk
	dad	d
	ret

; Find the header of physical sector skew[hstsec] on hsttrk, 20 tries
; (2 turns). Returns with interrupts off, just after the header.
findhdr:
	mvi	b,20
fh1:	push	b
	call	waitsec
	pop	b
	rc			; not ready
	call	armsync
	mvi	a,02h
	jc	fh2
	call	rdb		; volume: ignored
	call	rdb		; track
	lxi	h,hsttrk
	cmp	m
	mvi	a,01h
	jnz	fh9		; the wrong track: no use going on
	call	rdb		; sector
	lxi	h,physec
	cmp	m
	mvi	a,10h
	jnz	fh2
	mov	h,d
	call	rdb		; checksum
	cmp	h
	rz
	mvi	a,04h
fh2:	dcr	b
	jnz	fh1
fh9:	stc
	ret

; Read the data that follows the header into hstbuf.
rddata:	mvi	a,64		; about 7 bytes: past where a write began
rd1:	dcr	a
	jnz	rd1
	call	armsync
	mvi	a,20h
	rc
	lxi	h,hstbuf
	mvi	b,0
rd2:	in	DP.STAT
	rar
	jnc	rd2
	in	DP.DATA
	mov	m,a
	xra	d
	rlc
	mov	d,a
	inx	h
	dcr	b
	jnz	rd2
	mov	h,d
	call	rdb
	cmp	h
	rz
	mvi	a,08h
	stc
	ret

; Write hstbuf as the data that follows the header.
wrdata:	mvi	a,36		; about 4 bytes of gap
wr1:	dcr	a
	jnz	wr1
	lda	s7f
	ori	DF.WG
	out	DP.CTL
	mvi	c,10		; 10 zeros, then the sync byte
wr2:	xra	a
	call	wnb
	dcr	c
	jnz	wr2
	mvi	a,0fdh
	call	wnb
	mvi	d,0
	lxi	h,hstbuf
	mvi	b,0
wr3:	in	DP.STAT
	ora	a
	jp	wr3
	mov	a,m
	out	DP.DATA
	xra	d
	rlc
	mov	d,a
	inx	h
	dcr	b
	jnz	wr3
	mov	a,d		; the checksum, then 3 bytes so that it
	call	wnb		; leaves the shift register
	call	wnb
	call	wnb
	call	wnb
	lda	s7f
	out	DP.CTL		; write gate off
	ora	a		; NC
	ret

wnb:	mov	e,a
wnb1:	in	DP.STAT
	ora	a
	jp	wnb1
	mov	a,e
	out	DP.DATA
	ret

; Read a byte into A and E, adding it to the checksum in D.
rdb:	in	DP.STAT
	rar
	jnc	rdb
	in	DP.DATA
	mov	e,a
	xra	d
	rlc
	mov	d,a
	mov	a,e
	ret

; Arm the sync search and wait for it, about 26 bytes. Then read the
; sync byte and start the checksum. CY if no sync.
armsync:
	mvi	a,0fdh
	out	DP.SYNC
	in	DP.SYNC
	mvi	d,80
as1:	in	DP.CTL
	ani	DF.SD
	jnz	as2
	dcr	d
	jnz	as1
	stc
	ret
as2:	in	DP.DATA
	mvi	d,0
	ret

; Wait for the leading edge of a sector hole, not the index hole, which
; is halfway between the holes of sectors 9 and 0. No hole within 10 ms
; means the next one is a sector hole. A hole that comes within 10 ms may
; be the index hole: after it, 14 ms takes us past where the index hole
; or sector 0's hole could be. Returns with interrupts off, about 280 T
; after the edge. CY, A = 80H if the disk isn't turning.
waitsec:
	ei
	in	DP.CTL
	rar
	jc	ws3		; in a hole now
	lxi	h,5
	call	tdead
ws1:	in	DP.CTL
	rar
	jc	ws3
	call	tpast
	jc	ws1
	jmp	ws5		; none in 10 ms
ws3:	lxi	h,10		; wait for the hole to end
	call	tdead
ws4:	in	DP.CTL
	rar
	jnc	ws4a
	call	tpast
	jc	ws4
	jmp	wsnr
ws4a:	lxi	h,7
	call	twait
ws5:	di
	lxi	b,1200		; about 29 ms
ws6:	in	DP.CTL
	rar
	jc	ws7
	dcx	b
	mov	a,b
	ora	c
	jnz	ws6
wsnr:	ei
	mvi	a,80h
	stc
	ret
ws7:	mvi	a,20
ws8:	dcr	a
	jnz	ws8
	ora	a		; NC
	ret

; Tick deadlines. tdead: the deadline is HL ticks from now. tpast: CY
; while it hasn't come. Interrupts must be on.
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
	ral			; CY = the sign: now < deadline
	ret

; Wait HL ticks.
twait:	call	tdead
tw1:	call	tpast
	jc	tw1
	ret

; physec := the physical sector of host sector hstsec: 4 sectors apart,
; as on Heath's disks.
toskew:	lxi	h,skew
	lda	hstsec
	add	l
	mov	l,a
	jnc	tsk1
	inr	h
tsk1:	mov	a,m
	sta	physec
	ret
skew:	db	0,4,8,2,6,1,5,9,3,7
