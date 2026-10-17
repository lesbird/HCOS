; sysarea.asm - the emulated HDOS system area (2000H-227FH) and the
; page-zero hooks for RST 1 (clock) and RST 7 (SCALL).
;
; The cells follow a dump of HDOS 2.0 taken in the H89 emulator; see
; src/inc/hdos.inc.

RST1	equ	0008h
RST7	equ	0038h
.MFLAG	equ	2008h		; monitor user option byte
.CTLFLG	equ	2009h		; monitor front panel control byte
.CTL2FL	equ	2036h		; monitor OP2.CTL (port 362Q) byte
GPP	equ	0F2h		; port 362Q: bit 5 maps RAM over the ROM
GPP.RAM	equ	22h		; C-mode: RAM at 0000H, clock on (as the BIOS)
GPP.ROM	equ	02h		; H-mode: ROM at 0000H, clock on

; H-mode switching code, in HDOS's AIO work area (S.INT), which
; programs don't use: HDOS.COM itself is under the ROM in H-mode.
TRIN	equ	2121h		; RST 7 through the ROM: RAM in, dispatch
TROUT	equ	TRIN+9		; back to the program: ROM in, RET
				; (in C-mode just a RET)
TRRES	equ	TROUT+7		; a ^A/^B/^C handler's way back: POP PSW,
				; RET (it must be outside the ROM too)
B.CONIO	equ	54		; HCOS v2 BIOS entries (jump table offsets):
B.TICKO	equ	57		; console interrupt, ROM clock hook
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

	lxi	h,trtab			; mode switching code
	lxi	d,TRIN
	mvi	b,trlen
	call	move
	lda	hmode
	ora	a
	jnz	si4
	mvi	a,0C9h			; C-mode: TROUT is a RET
	sta	TROUT
	jmp	si5
si4:	lhld	BOOT+1			; H-mode: the slots are reached with
	lxi	d,B.CONIO-3		; the ROM in, so they go to the BIOS,
	dad	d			; above 2000H: its console handler
	xchg				; (which takes a key if there is
	lxi	h,.UIVEC		; one)
	mvi	b,7
si4a:	inx	h
	mov	m,e
	inx	h
	mov	m,d
	inx	h
	dcr	b
	jnz	si4a
	xchg				; the clock: the BIOS's tick count
	lxi	d,B.TICKO-B.CONIO	; (the ROM calls it, with UO.CLK)
	dad	d
	shld	UIV.CLK+1
	lxi	h,TRIN			; RST 7 comes to TRIN; monitor set as
	shld	UIV.SC+1		; HDOS sets it
	mvi	a,81h
	sta	.MFLAG
	mvi	a,80h
	sta	.CTL2FL
	mvi	a,0D0h
	sta	.CTLFLG
si5:
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
	lhld	pentry			; (through TROUT: ROM in for H-mode)
	push	h
	jmp	TROUT

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

; Copied to TRIN: entering an SCALL from H-mode, and leaving one.
trtab:	push	psw
	mvi	a,GPP.RAM
	out	GPP
	pop	psw
	jmp	scdisp
	push	psw
	mvi	a,GPP.ROM
	out	GPP
	pop	psw
	ret
	pop	psw			; TRRES
	ret
trlen	equ	$-trtab

sexita:	xra	a
	SCALL	.EXIT
sexital	equ	$-sexita

; A program called into resident HDOS through S.JUMPS: not supported.
; Each slot jumps to its own stub here, which names it.

; .GDA (HDOS 3.0) - DE = device name: HL -> its driver JMP, BC -> its
; device table entry. CY, A = EC.UND and HL = BC = 0 if unknown.
sgda:	lxi	h,devtab
gda1:	mov	a,m
	ora	a
	jz	gda3
	mov	b,h
	mov	c,l
	mov	a,m			; name (low byte first, as a word)
	inx	h
	cmp	e
	jnz	gda2
	mov	a,m
	cmp	d
	jnz	gda2
	inx	h			; DEV.JMP
	inx	h
	xra	a
	ret
gda2:	lxi	h,DEVELEN
	dad	b
	jmp	gda1
gda3:	mov	h,a
	mov	l,a
	mov	b,a
	mov	c,a
	mvi	a,EC.UND
	stc
	ret

; phexo - print A as 3 octal digits through BDOS (for diagnostics).
phexo:	push	psw
	rlc
	rlc
	ani	3
	call	phexo1
	pop	psw
	push	psw
	rrc
	rrc
	rrc
	ani	7
	call	phexo1
	pop	psw
	ani	7
phexo1:	adi	'0'
	mov	e,a
	mvi	c,C_WRITE
	jmp	BDOS


svrst1:	ds	3			; CP/M's page zero RST 1 and RST 7
svrst7:	ds	3

; Date given to programs. CP/M 2.2 has no clock, so it is fixed.

