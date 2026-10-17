; bdos.asm - the HCOS BDOS: CP/M 2.2 compatible console and file system
;
; From HCOS version 1, where it replaced DRI's BDOS under the Heath
; BIOS. In version 2 it sits in the reserved tracks at E200H, with the
; shell below it and HCOS's own BIOS above it. Written from the CP/M 2.2
; interface (DRI CP/M 2.2 Interface Guide); no DRI code.
;
; Calls: C = function, DE = parameter. Results in A (= L) and HL (B =
; H), as CP/M 2.2 returns them.
;
; Code and tables go in the reserved tracks; the variables follow them,
; up to the BIOS at F000H, and aren't stored on disk.

	.8080
	include	cpm.inc
	include	layout.inc

; BDOSB, KXVEC and the BIOS entries come from layout.inc.

IOBYTE	equ	0003h
CDISK	equ	0004h		; user (high 4 bits) and drive

CR	equ	0Dh
LF	equ	0Ah
TAB	equ	09h
BS	equ	08h
RUB	equ	7Fh
CTLC	equ	03h
CTLE	equ	05h
CTLP	equ	10h
CTLR	equ	12h
CTLS	equ	13h
CTLU	equ	15h
CTLX	equ	18h

EMPTY	equ	0E5h		; empty directory entry
FWF	equ	80h		; in FCB S2: file not written since open

; FCB offsets
F.DR	equ	0
F.T1	equ	9		; R/O attribute is bit 7
F.EX	equ	12
F.S2	equ	14
F.RC	equ	15
F.MAP	equ	16
F.CR	equ	32
F.R0	equ	33

	org	BDOSB

serial:	db	0,0,0,0,0,0	; (DRI's serial number; nothing checks it)
bdose:	jmp	bdent		; entry, BDOSB+6
	; Error vectors at the same place as DRI's (some programs patch
	; them): bad sector, select, R/O disk, R/O file.
	dw	perr,selerr,roderr,roferr
	; Hook for the HDOS extension (KXVEC): the shell puts a JMP to it
	; here at every boot. It is offered each FCB call; CY = not its.
kxv:	stc
	ret
	nop
	assert	kxv == KXVEC
kxnd:	db	0		; an HDOS disk was found, with no extension
	assert	kxnd == KXNEED
	assert	$ == BDSUMB

; ---- Entry and exit ----

bdent:	xchg
	shld	info
	xchg
	mov	a,e
	sta	linfo
	lxi	h,0
	shld	aret
	dad	sp
	shld	entsp
	lxi	sp,stack
	xra	a
	sta	resel
	lxi	h,goback
	push	h
	mov	a,c
	sta	fnum
	cpi	NFUNC
	rnc
	mov	c,e			; C = byte parameter
	lxi	h,ftab
	mov	e,a
	mvi	d,0
	dad	d
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	lhld	info
	xchg				; DE = parameter
	pchl

ftab:	dw	wboot,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12
	dw	f13,f14,f15,f16,f17,f18,f19,f20,f21,f22,f23,f24
	dw	f25,f26,f27,f28,f29,f30,f31,f32,f33,f34,f35,f36
	dw	f37,goback,goback,f40
NFUNC	equ	($-ftab)/2

; Back to the caller: put an FCB's drive byte back and the current
; drive back in the BIOS, then return aret in A, L and B, H.
goback:	lda	resel
	ora	a
	jz	retmon
	lhld	info
	lda	fcbdsk
	mov	m,a
	lda	olddsk
	call	seldrv
retmon:	lhld	entsp
	sphl
	lhld	aret
	mov	a,l
	mov	b,h
	ret

; Results
setret:	sta	aret			; byte result
	ret
ret1:	mvi	a,1
	jmp	setret
retff:	mvi	a,0FFh
	jmp	setret

wboot:	jmp	BOOT

; ---- Console ----

; f1 - console input with echo
f1:	call	conech
	jmp	setret

; conech - read a char and echo it unless it's a control other than
; CR, LF, TAB or BS.
conech:	call	conin
	cpi	' '
	jnc	ce1
	cpi	CR
	jz	ce1
	cpi	LF
	jz	ce1
	cpi	TAB
	jz	ce1
	cpi	BS
	rnz
ce1:	push	psw
	mov	c,a
	call	tabout
	pop	psw
	ret

; conin - next char: the one conbrk kept, or from the BIOS.
conin:	lxi	h,kbchar
	mov	a,m
	mvi	m,0
	ora	a
	rnz
	jmp	B.CONIN

; conbrk - is a char waiting? A = 1 if so. Handles ^S (stop until a
; key; ^C then reboots) on the way.
conbrk:	lda	kbchar
	ora	a
	jnz	cb1
	call	B.CONST
	ani	1
	rz
	call	B.CONIN
	cpi	CTLS
	jnz	cb0
	call	B.CONIN
	cpi	CTLC
	jz	BOOT
	xra	a
	ret
cb0:	sta	kbchar
cb1:	mvi	a,1
	ret

; f2 - console output with tab expansion
f2:	jmp	tabout

; conout - C to the console (and the printer after ^P), keeping the
; column. Stops for ^S.
conout:	lda	compcol			; only counting columns?
	ora	a
	jnz	co1
	push	b
	call	conbrk
	pop	b
	push	b
	call	B.CONOUT
	pop	b
	push	b
	lda	listcp
	ora	a
	cnz	B.LIST
	pop	b
co1:	mov	a,c			; column
	lxi	h,column
	cpi	RUB
	rz
	inr	m
	cpi	' '
	rnc
	dcr	m
	mov	a,m
	ora	a
	rz
	mov	a,c
	cpi	BS
	jnz	co2
	dcr	m
	ret
co2:	cpi	CR
	rnz
	mvi	m,0
	ret

; tabout - like conout, but a TAB becomes spaces to the next stop.
tabout:	mov	a,c
	cpi	TAB
	jnz	conout
to1:	mvi	c,' '
	call	conout
	lda	column
	ani	7
	jnz	to1
	ret

; ctlout - C as conout, controls as ^X.
ctlout:	mov	a,c
	cpi	' '
	jnc	conout
	push	psw
	mvi	c,'^'
	call	conout
	pop	psw
	ori	40h
	mov	c,a
	jmp	conout

; crlf
crlf:	mvi	c,CR
	call	conout
	mvi	c,LF
	jmp	conout

; pstr - print the string at HL up to '$' (with tab expansion).
pstr:	mov	a,m
	cpi	'$'
	rz
	inx	h
	push	h
	mov	c,a
	call	tabout
	pop	h
	jmp	pstr

f3:	call	B.READER
	jmp	setret
f4:	jmp	B.PUNCH
f5:	jmp	B.LIST

; f6 - direct console I/O: E = FFH reads (0 if none), else outputs E.
f6:	mov	a,c
	inr	a
	jz	f6in
	jmp	B.CONOUT
f6in:	call	B.CONST
	ora	a
	jz	setret
	call	B.CONIN
	jmp	setret

f7:	lda	IOBYTE
	jmp	setret
f8:	lxi	h,IOBYTE
	mov	m,c
	ret

; f9 - print string at DE up to '$'
f9:	xchg
	jmp	pstr

f11:	call	conbrk
	jmp	setret

f12:	lxi	h,0022h			; CP/M 2.2
	shld	aret
	ret

; f10 - read a line into the buffer at DE: max, count, chars.
f10:	lda	column
	sta	strtcol
	lxi	h,0
	shld	rdbuf			; L = count, H = 0
f10l:	call	conin
	cpi	CTLP
	jnz	f10a
	lxi	h,listcp		; toggle printer echo
	mov	a,m
	xri	1
	mov	m,a
	jmp	f10l
f10a:	cpi	CR
	jz	f10end
	cpi	LF
	jz	f10end
	cpi	CTLE			; physical end of line
	jnz	f10b
	call	crlf
	jmp	f10l
f10b:	cpi	BS
	jz	f10bs
	cpi	RUB
	jnz	f10c
	lda	rdbuf			; rubout: echo the char deleted
	ora	a
	jz	f10l
	call	f10last
	mov	c,m
	dcr	a
	sta	rdbuf
	call	ctlout
	jmp	f10l
f10c:	cpi	CTLU
	jz	f10u
	cpi	CTLX
	jz	f10x
	cpi	CTLR
	jz	f10r
	cpi	CTLC			; ^C first thing: reboot
	jnz	f10put
	lda	rdbuf
	ora	a
	jz	BOOT
	mvi	a,CTLC
f10put:	mov	b,a			; store it, if there's room
	lhld	info
	lda	rdbuf
	cmp	m
	jnc	f10l
	inr	a
	sta	rdbuf
	call	f10last
	mov	m,b
	mov	c,b
	call	ctlout
	lhld	info
	lda	rdbuf
	cmp	m
	jc	f10l
f10end:	lhld	info			; done: count in the buffer
	inx	h
	lda	rdbuf
	mov	m,a
	mvi	c,CR
	jmp	conout

; f10last - HL -> the last char in the buffer (count in A). Keeps A.
f10last: lhld	info
	inx	h
	push	psw
	call	dada
	pop	psw
	ret

; ^H: delete the last char and back up to its column.
f10bs:	lda	rdbuf
	ora	a
	jz	f10l
	dcr	a
	sta	rdbuf
	call	f10col			; column the line would end at now
	lxi	h,column
f10bs1:	mov	a,m
	cmp	b
	jz	f10l
	jc	f10l
	mvi	c,BS
	call	conout
	mvi	c,' '
	call	conout
	mvi	c,BS
	call	conout
	jmp	f10bs1

; ^X: back up to the start of the line.
f10x:	xra	a
	sta	rdbuf
	lda	strtcol
	mov	b,a
	lxi	h,column
	jmp	f10bs1

; ^U: new line, start again. ^R: new line, type the line again.
f10u:	xra	a
	sta	rdbuf
f10r:	mvi	c,'#'
	call	conout
	call	crlf
	lda	strtcol			; indent to where it started
	mov	b,a
f10r1:	lda	column
	cmp	b
	jnc	f10r2
	mvi	c,' '
	call	conout
	jmp	f10r1
f10r2:	lda	rdbuf			; and type what is there
	mov	b,a
	lhld	info
	inx	h
f10r3:	mov	a,b
	ora	a
	jz	f10l
	inx	h
	mov	c,m
	push	h
	push	b
	call	ctlout
	pop	b
	pop	h
	dcr	b
	jmp	f10r3

; f10col - B = the column the line in the buffer would end at.
f10col:	lda	column
	push	psw
	lda	strtcol
	sta	column
	mvi	a,1
	sta	compcol
	lda	rdbuf
	mov	b,a
	lhld	info
	inx	h
f10c1:	mov	a,b
	ora	a
	jz	f10c2
	inx	h
	mov	c,m
	push	h
	push	b
	call	ctlout
	pop	b
	pop	h
	dcr	b
	jmp	f10c1
f10c2:	xra	a
	sta	compcol
	lda	column
	mov	b,a
	pop	psw
	sta	column
	ret

; ---- Errors ----

perr:	lxi	h,mbad			; bad sector: a key goes on, ^C
	call	errmsg			; reboots
	call	conin
	cpi	CTLC
	jz	BOOT
	ret
selerr:	lxi	h,msel
	jmp	errboot
roderr:	lxi	h,mro
	jmp	errboot
roferr:	lxi	h,mrof
errboot: call	errmsg
	call	conin
	jmp	BOOT

; errmsg - "Bdos Err On d: " and the message at HL.
; (The drive letter is printed, not put in the message: warm boot
; checks the BDOS's code by its sum.)
errmsg:	push	h
	call	crlf
	lxi	h,merr
	call	pstr
	lda	seldsk
	adi	'A'
	mov	c,a
	call	conout
	lxi	h,mdsk
	call	pstr
	pop	h
	jmp	pstr

merr:	db	'Bdos Err On $'
mdsk:	db	': $'
mbad:	db	'Bad Sector$'
msel:	db	'Select$'
mro:	db	'R/O$'
mrof:	db	'File R/O$'

	include	kfs.asm

; ---- Small helpers ----

; dada - HL = HL + A. Uses A.
dada:	add	l
	mov	l,a
	rnc
	inr	h
	ret

; move - copy C bytes from HL to DE. DE, HL advance.
move:	mov	a,c
	ora	a
	rz
	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	c
	jmp	move

; cmpde - compare HL with DE: CY if HL < DE, Z if equal.
cmpde:	mov	a,h
	cmp	d
	rnz
	mov	a,l
	cmp	e
	ret

	assert	$ <= BIOSB		; code and tables must load

; ---- Variables (not loaded; set up by f13 and the first call) ----

info:	ds	2			; DE at the call
fnum:	ds	1			; function number
linfo:	ds	1			; E at the call
aret:	ds	2			; result
entsp:	ds	2			; caller's SP
resel:	ds	1			; FCB drive was switched
fcbdsk:	ds	1			; FCB's drive byte
olddsk:	ds	1			; current drive to go back to
kbchar:	ds	1
column:	ds	1
strtcol: ds	1
compcol: ds	1
listcp:	ds	1
rdbuf:	ds	2
	include	kfsvar.asm
	ds	48			; 24 levels, as DRI's
stack	equ	$

	assert	$ <= BIOSB
