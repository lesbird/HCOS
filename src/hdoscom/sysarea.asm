; sysarea.asm - the emulated HDOS system area (2000H-227FH) and the
; page-zero hooks for RST 1 (clock) and RST 7 (SCALL).
;
; The cells follow a dump of HDOS 2.0 taken in the H89 emulator; see
; src/inc/hdos.inc.

RST1	equ	0008h
RST7	equ	0038h
.MFLAG	equ	2008h		; monitor user option byte
UIV.CLK	equ	.UIVEC		; RST 1 slot
UIV.SC	equ	.UIVEC+18	; RST 7 slot

; sysinit - clear and fill in the system area, hook RST 1 and RST 7.
sysinit:
	lxi	h,2000h			; clear 2000H-227FH
si1:	mvi	m,0
	inx	h
	mov	a,h
	cpi	22h
	jnz	si1
	mov	a,l
	cpi	80h
	jnz	si1

	; RAM vector slots RST 1-7: a JMP to a plain EI/RET, except the
	; clock and SCALL slots.
	lxi	h,.UIVEC
	mvi	b,7
si2:	mvi	m,0C3h			; JMP
	inx	h
	mvi	m,low vnull
	inx	h
	mvi	m,high vnull
	inx	h
	dcr	b
	jnz	si2
	lxi	h,sclkx			; RST 1: return from the clock tick
	shld	UIV.CLK+1
	lxi	h,scdisp			; RST 7: SCALL
	shld	UIV.SC+1

	lxi	h,S.JUMPS		; system entry points: report, exit
	lxi	d,sjtab
	mvi	b,6
si3:	mvi	m,0C3h
	inx	h
	mov	m,e
	inx	h
	mov	m,d
	inx	h
	push	h
	lxi	h,sjlen
	dad	d
	xchg
	pop	h
	dcr	b
	jnz	si3
	lxi	h,gup			; S.GUP is real: PIP uses it
	shld	S.GUP+1
	lxi	h,devtab		; device and overlay tables
	shld	S.DFWA
	lxi	h,ovltab
	shld	S.OFWA
	mvi	a,1			; system disk mounted
	sta	S.MOUNT
	lhld	psscr			; scratch area
	shld	S.SCR

	lxi	h,sexita		; S.EXITA: XRA A / SCALL .EXIT
	lxi	d,S.EXITA
	mvi	b,sexital
	call	move

	lxi	h,sdate			; date
	lxi	d,S.DATE
	mvi	b,9
	call	move
	lhld	sdatc
	shld	S.DATC
	lxi	h,0FFFFh
	shld	S.HIMEM
	lhld	memtop
	shld	S.SYSM
	mvi	a,8Ah			; BKS, 2SB, BKM: as HDOS 2.0 sets it
	sta	S.CONTY			; for the H19
	mvi	a,80
	sta	S.CONWI
	mvi	a,1
	sta	S.CUSOR

	; Page zero: save what CP/M has there and hook RST 1 and RST 7.
	di
	lxi	h,RST1
	lxi	d,svrst1
	mvi	b,3
	call	move
	lxi	h,RST7
	lxi	d,svrst7
	mvi	b,3
	call	move
	lhld	RST1+1			; the BIOS clock handler
	shld	bclk
	mvi	a,0C3h
	sta	RST1
	sta	RST7
	lxi	h,sclk
	shld	RST1+1
	lxi	h,UIV.SC		; RST 7 goes through the RAM slot
	shld	RST7+1
	ei
	ret

; sysdone - put page zero back as CP/M had it.
sysdone:
	di
	lxi	h,svrst1
	lxi	d,RST1
	mvi	b,3
	call	move
	lxi	h,svrst7
	lxi	d,RST7
	mvi	b,3
	call	move
	ei
	ret

; launch - start the loaded program. HL -> argument string (NUL
; terminated). Like SYSCMD's PCL, the string goes just below STACK
; and SP points at it; with no arguments SP = STACK.
launch:	mov	a,m
	ora	a
	jz	la3			; no arguments
	mov	d,h			; find the NUL
	mov	e,l
la1:	mov	a,m
	ora	a
	jz	la2
	cpi	'a'			; upper case, as PCL does
	jc	la1a
	cpi	'z'+1
	jnc	la1a
	sui	20h
	mov	m,a
la1a:	inx	h
	jmp	la1
la2:	; copy back to front, from the NUL at HL down to DE
	lxi	b,STACK
la2a:	mov	a,m
	dcx	b
	stax	b
	mov	a,l
	cmp	e
	jnz	la2b
	mov	a,h
	cmp	d
	jz	la2c
la2b:	dcx	h
	jmp	la2a
la2c:	mov	h,b
	mov	l,c
	jmp	la4
la3:	lxi	h,STACK
la4:	sphl
	lhld	pentry
	pchl

; Clock tick: count it in .TICCNT as the monitor ROM does, then let
; the CP/M BIOS handle the interrupt.
sclk:	push	psw
	push	h
	lhld	.TICCNT
	inx	h
	shld	.TICCNT
	pop	h
	pop	psw
	db	0C3h			; JMP to the BIOS handler
bclk:	dw	0

sclkx:
vnull:	ei
	ret

; move - copy B bytes from HL to DE.
move:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	move
	ret

sexita:	xra	a
	SCALL	.EXIT
sexital	equ	$-sexita

; A program called into resident HDOS through S.JUMPS: not supported.
; Each slot jumps to its own stub here, which names it.
sjtab:	mvi	a,0
	jmp	sjump
sjlen	equ	$-sjtab
	mvi	a,1
	jmp	sjump
	mvi	a,2
	jmp	sjump
	mvi	a,3
	jmp	sjump
	mvi	a,4
	jmp	sjump
	mvi	a,5
sjump:	lxi	sp,hcstk
	add	a			; DE -> name
	add	a
	add	a
	mov	e,a
	mvi	d,0
	lxi	h,sjnam
	dad	d
	push	h
	lxi	d,msjump
	mvi	c,C_WRITESTR
	call	BDOS
	pop	d
	mvi	c,C_WRITESTR
	call	BDOS
	jmp	hexit
msjump:	db	0dh,0ah,'HDOS.COM: program called HDOS internals: $'
sjnam:	db	'S.SDD',0dh,0ah,'$'
	db	'S.FASER$'
	db	'S.DIREA$'
	db	'S.FCI',0dh,0ah,'$'
	db	'S.SCI',0dh,0ah,'$'
	db	'S.GUP',0dh,0ah,'$'

; S.GUP - HL -> a unit table pointer (DEV.UNT), A = unit: HL -> that
; unit's entry. Uses F, H, L.
gup:	push	psw
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	pop	psw
	push	psw
	ani	7
	rlc
	rlc
	rlc
	call	rdadap
	pop	psw
	ret

; Device table (DEVDEF): name, residence, JMP driver, flags, mounted
; unit mask, units, -> unit table, driver length and group. SY: and
; DK: are both the CP/M drives.
DEVELEN	equ	14
DR.IMPR	equ	03h		; in memory, permanent
devtab:	db	'SY',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.DIR,0Fh,NUNIT
	dw	unttab,0
	db	0
	db	'DK',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.DIR,0Fh,NUNIT
	dw	unttab,0
	db	0
	db	'TT',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.CHR,1,1
	dw	chrunt,0
	db	0
	db	'LP',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.CHR,1,1
	dw	chrunt,0
	db	0
	db	0			; end
chrunt:	db	DT.CHR,0
	dw	0,0,0

; Overlay table: both HDOS overlays in memory and resident, as they
; are in effect (PIP reads OVL.FLB).
ovltab:	dw	0,0,0
	db	3,0
	dw	0,0,0
	db	3,0

; A program called a device driver directly: not supported.
ddrv.x:	mvi	a,EC.DDA
	stc
	ret

svrst1:	ds	3			; CP/M's page zero RST 1 and RST 7
svrst7:	ds	3

; Date given to programs. CP/M 2.2 has no clock, so it is fixed.
sdate:	db	'01-Jan-80'
sdatc:	dw	((80-70) << 9) + (1 << 5) + 1	; coded: yyyyyyy mmmm ddddd

