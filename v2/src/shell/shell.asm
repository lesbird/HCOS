; shell.asm - the HCOS v2 shell
;
; Version 1's HCCP, in the reserved tracks at DA00H. It behaves like the
; CP/M 2.2 CCP: the same entry points and command buffer, the same
; built-in commands and messages, SUBMIT through $$$.SUB, .COM programs
; loaded at 0100H. On top of that:
;   - CAT is DIR, as on HDOS;
;   - NAME runs NAME.ABS, through HDOS.COM, when there is no NAME.COM.
;     (Until HDOS programs run natively, phase 5.)
; When the BDOS has found an HDOS disk (KXNEED), the shell loads the HDOS
; extension HDOSFS.SYS at the next boot (kxload.asm).
; Written from the CP/M 2.2 documentation; no DRI code.

	.8080
	include	cpm.inc
	include	layout.inc

FCB2	equ	DFCB+16
IOCDISK	equ	0004h		; user << 4 + drive

	org	SHELLB

	jmp	ccpcmd		; with the command in the buffer
	jmp	ccpclr		; without
cbmax:	db	127		; command buffer, as f10 wants it
cblen:	db	0
cbuf:	ds	128
subfcb:	db	1,'$$$     SUB',0,0,0,0
	ds	17
	db	0
	assert	$ == SHSUMB	; warm boot checks the code from here

; ---- Start ----

ccpclr:	xra	a
	sta	cblen
ccpcmd:	lxi	sp,stack
	push	b		; C = user << 4 + drive
	mov	a,c
	rrc
	rrc
	rrc
	rrc
	ani	0Fh
	mov	e,a
	push	d
	call	setusr
	mvi	c,13		; reset disks: FFH if $$$.SUB is there
	call	sys
	sta	submit
	call	kxinit		; the HDOS extension: load or hook
	pop	d
	call	setusr
	pop	b
	mov	a,c
	ani	0Fh
	sta	cdisk
	call	seldsk
	lda	cblen		; a command waiting (auto-start)?
	ora	a
	jnz	docmd

; ---- The command loop ----

prompt:	lxi	sp,stack
	call	crlf
	lda	cdisk
	adi	'A'
	call	putc
	mvi	a,'>'
	call	putc
	call	readcmd
docmd:	lxi	h,cbuf		; upper case, NUL at the end
	lda	cblen
	mov	b,a
dc1:	mov	a,b
	ora	a
	jz	dc2
	mov	a,m
	call	upper
	mov	m,a
	inx	h
	dcr	b
	jmp	dc1
dc2:	mvi	m,0
	lxi	h,cbuf
	shld	cptr
	xra	a
	sta	hdosrun
	call	setcdk		; 0004: current user and drive
	lxi	d,DFCB		; the command
	call	fillfcb
	jnz	cmderr		; ambiguous: ?
	lhld	cptr		; the tail starts after it
	shld	cptr0
	lda	DFCB		; "d:" alone: change drive
	ora	a
	jz	dc3
	lda	DFCB+1
	cpi	' '
	jnz	dc3
	lda	DFCB
	dcr	a
	sta	cdisk
	call	seldsk
	jmp	endcmd
dc3:	lda	DFCB		; built-in? (not with a drive)
	ora	a
	jnz	trans
	lxi	h,cmdtab
	mvi	c,0
dc4:	mov	a,m
	ora	a
	jz	trans
	lxi	d,DFCB+1
	mvi	b,4
	push	h
dc5:	ldax	d
	cmp	m
	jnz	dc6
	inx	h
	inx	d
	dcr	b
	jnz	dc5
	ldax	d		; and nothing more in the name
	cpi	' '
	jnz	dc6
	pop	h
	mov	a,c		; to its routine
	add	a
	lxi	h,cmdjmp
	mov	e,a
	mvi	d,0
	dad	d
	mov	e,m
	inx	h
	mov	d,m
	xchg
	pchl
dc6:	pop	h
	lxi	d,4
	dad	d
	inr	c
	jmp	dc4

cmdtab:	db	'DIR ERA TYPESAVEREN USERCAT ',0
cmdjmp:	dw	cdir,cera,ctype,csave,cren,cuser,cdir

; endcmd - the command line must be finished.
endcmd:	call	skipsp
	ora	a
	jz	prompt
cmderr:	call	crlf		; echo the word in error and "?"
	lhld	cword
ce1:	mov	a,m
	cpi	' '
	jz	ce2
	ora	a
	jz	ce2
	call	putc
	inx	h
	jmp	ce1
ce2:	mvi	a,'?'
	call	putc
	call	crlf
	call	delsub
	jmp	prompt

; ---- Reading a command ----

; readcmd - from $$$.SUB if SUBMIT is running, else the console.
readcmd: lda	submit
	ora	a
	jz	rc.con
	lxi	d,subfcb	; $$$.SUB, on drive A
	mvi	c,F_OPEN
	call	sys
	inr	a
	jz	rc.end
	lda	subfcb+15	; last record holds the next command
	dcr	a
	jm	rc.end
	sta	subfcb+32
	lxi	d,cblen
	mvi	c,F_DMAOFF
	call	sys
	lxi	d,subfcb
	mvi	c,F_READ
	call	sys
	ora	a
	jnz	rc.end
	lxi	h,subfcb+14	; drop the record: S2 = 0 (written),
	mvi	m,0		; one record less, close
	inx	h
	dcr	m
	lxi	d,subfcb
	mvi	c,F_CLOSE
	call	sys
	inr	a
	jz	rc.end
	lda	cblen		; show it
	mov	b,a
	lxi	h,cbuf
rc1:	mov	a,b
	ora	a
	jz	rc2
	mov	a,m
	call	putc
	inx	h
	dcr	b
	jmp	rc1
rc2:	call	brkkey		; a key stops SUBMIT
	jz	rc3
	call	delsub
	jmp	prompt
rc3:	lxi	d,TBUF
	mvi	c,F_DMAOFF
	jmp	sys
rc.end:	call	delsub
rc.con:	call	setcdk		; (as CP/M's CCP: user and drive in
	lxi	d,cbmax		; 0004 while typing, the drive only
	mvi	c,10		; after)
	call	sys
	call	setdk
	jmp	rc3

; delsub - SUBMIT is over: delete $$$.SUB.
delsub:	lxi	h,submit
	mov	a,m
	ora	a
	rz
	mvi	m,0
	lxi	d,subfcb
	mvi	c,F_DELETE
	jmp	sys

; brkkey - NZ if a key was typed (and take it).
brkkey:	mvi	c,C_STAT
	call	sys
	ora	a
	rz
	mvi	c,C_READ
	call	sys
	ori	1
	ret

; ---- Parsing ----

; fillfcb - parse the next word at cptr into the FCB at DE: drive,
; name, type ("*" fills with "?"), the rest 0. Z if unambiguous.
fillfcb: push	d
	call	skipsp
	shld	cword
	pop	d
	push	d
	xra	a		; drive 0
	stax	d
	inx	d
	mvi	b,11		; blank name and type
	mvi	a,' '
ff0:	stax	d
	inx	d
	dcr	b
	jnz	ff0
	mvi	b,21		; extent ... current record: 0
	xra	a
ff0b:	stax	d
	inx	d
	dcr	b
	jnz	ff0b
	pop	d
	sta	qtot
	lhld	cptr
	mov	a,m		; "d:"
	ora	a
	jz	ff9
	inx	h
	mov	a,m
	dcx	h
	cpi	':'
	jnz	ff1
	mov	a,m
	sui	'A'-1
	stax	d
	inx	h
	inx	h
ff1:	inx	d
	mvi	b,8
	call	ffpart
	mov	a,m
	cpi	'.'
	jnz	ff2
	inx	h
	mvi	b,3
	call	ffpart
ff2:	shld	cptr
ff9:	lda	qtot
	ora	a
	ret

; ffpart - B name chars at HL to DE; "*" fills the rest with "?".
; DE ends past the field, HL at the delimiter.
ffpart:	call	delim
	jz	fp3
	cpi	'*'
	mvi	a,'?'
	jz	fp2		; (HL stays on the "*")
	mov	a,m
	inx	h
fp2:	cpi	'?'
	jnz	fp2a
	push	h
	lxi	h,qtot
	inr	m
	pop	h
fp2a:	stax	d
	inx	d
	dcr	b
	jnz	ffpart
fp2b:	call	delim		; skip what doesn't fit
	rz
	inx	h
	jmp	fp2b
fp3:	mov	a,b		; the rest stays blank
	add	e
	mov	e,a
	mvi	a,0
	adc	d
	mov	d,a
	ret

; delim - A = the char at HL; Z if it ends a name part.
delim:	mov	a,m
	ora	a
	rz
	cpi	' '
	rz
	cpi	'.'
	rz
	cpi	'='
	rz
	cpi	','
	rz
	cpi	';'
	rz
	cpi	'<'
	rz
	cpi	'>'
	rz
	cpi	'_'
	rz
	cpi	':'
	ret

; skipsp - HL = cptr past blanks; A = the char there.
skipsp:	lhld	cptr
ss1:	mov	a,m
	cpi	' '
	jnz	ss2
	inx	h
	jmp	ss1
ss2:	shld	cptr
	ret

upper:	cpi	'a'
	rc
	cpi	'z'+1
	rnc
	sui	20h
	ret

; ---- Built-in commands ----

; DIR [afn] / CAT [afn]
cdir:	lxi	d,DFCB
	call	fillfcb
	lda	DFCB+1		; no name: *.*
	cpi	' '
	jnz	di1
	lxi	h,DFCB+1
	mvi	b,11
di0:	mvi	m,'?'
	inx	h
	dcr	b
	jnz	di0
di1:	mvi	c,F_SFIRST
	lxi	d,DFCB
	call	sys
	cpi	0FFh
	jz	nofile
	mvi	b,0		; B = files on this line
di2:	add	a		; HL -> entry in TBUF
	add	a
	add	a
	add	a
	add	a
	adi	TBUF and 0FFh
	mov	l,a
	mvi	h,TBUF shr 8
	push	h
	lxi	d,10		; SYS files aren't shown
	dad	d
	mov	a,m
	pop	h
	ral
	jc	di5
	mov	a,b
	ani	3
	jnz	di3
	call	crlf		; new line: "d"
	call	fcbdk
	adi	'A'
	call	putc
	jmp	di4
di3:	mvi	a,' '
	call	putc
di4:	mvi	a,':'
	call	putc
	mvi	a,' '
	call	putc
	inx	h
	mvi	c,8
	call	putn
	mvi	a,' '
	call	putc
	mvi	c,3
	call	putn
	inr	b
di5:	push	b
	call	brkkey
	pop	b
	jnz	di6
	push	b
	mvi	c,F_SNEXT
	lxi	d,DFCB
	call	sys
	pop	b
	cpi	0FFh
	jnz	di2
di6:	jmp	endcmd

; putn - print C chars at HL (attribute bits off).
putn:	mov	a,m
	ani	7Fh
	call	putc
	inx	h
	dcr	c
	jnz	putn
	ret

nofile:	lxi	h,mnofil
	call	pmsg
	jmp	prompt

; ERA afn
cera:	lxi	d,DFCB
	call	fillfcb
	lxi	h,DFCB+1	; *.*: ask
	mvi	b,11
er1:	mov	a,m
	cpi	'?'
	jnz	er2
	inx	h
	dcr	b
	jnz	er1
	lxi	h,mall
	call	pmsg
	call	readcmd0
	lda	cblen
	ora	a
	jz	prompt
	lda	cbuf
	call	upper
	cpi	'Y'
	jnz	prompt
	lxi	h,cbuf		; (the line is gone now)
	mvi	m,0
	shld	cptr
er2:	lxi	d,DFCB
	mvi	c,F_DELETE
	call	sys
	inr	a
	jz	nofile
	jmp	endcmd

; readcmd0 - a line from the console.
readcmd0: lxi	d,cbmax
	mvi	c,10
	jmp	sys

; TYPE ufn
ctype:	lxi	d,DFCB
	call	fillfcb
	jnz	cmderr
	lxi	d,DFCB
	mvi	c,F_OPEN
	call	sys
	inr	a
	jz	cmderr
	call	crlf
ty1:	lxi	d,DFCB
	mvi	c,F_READ
	call	sys
	ora	a
	jz	ty2
	dcr	a
	jz	endcmd
	lxi	h,mrderr
	call	pmsg
	jmp	prompt
ty2:	lxi	h,TBUF
	mvi	b,128
ty3:	mov	a,m
	cpi	1Ah
	jz	endcmd
	call	putc
	inx	h
	push	h
	push	b
	call	brkkey
	pop	b
	pop	h
	jnz	endcmd
	dcr	b
	jnz	ty3
	jmp	ty1

; SAVE n ufn
csave:	call	number
	push	psw
	lxi	d,DFCB
	call	fillfcb
	jnz	cmderr
	lxi	d,DFCB
	mvi	c,F_DELETE
	call	sys
	lxi	d,DFCB
	mvi	c,F_MAKE
	call	sys
	inr	a
	jz	nospace
	pop	psw		; 2n records from 0100H
	mov	b,a
	lxi	h,TPA
sv1:	mov	a,b
	ora	a
	jz	sv2
	dcr	b
	call	sv.rec
	jnz	nospace
	call	sv.rec
	jnz	nospace
	jmp	sv1
sv2:	lxi	d,DFCB
	mvi	c,F_CLOSE
	call	sys
	inr	a
	jz	nospace
	jmp	endcmd
sv.rec:	push	b
	push	h
	xchg
	mvi	c,F_DMAOFF
	call	sys
	lxi	d,DFCB
	mvi	c,F_WRITE
	call	sys
	pop	h
	lxi	d,128
	dad	d
	pop	b
	ora	a
	ret
nospace: lxi	h,mnospc
	call	pmsg
	jmp	prompt

; REN new=old
cren:	lxi	d,DFCB
	call	fillfcb
	jnz	cmderr
	lda	DFCB
	push	psw
	call	skipsp		; "=" or "_"
	cpi	'='
	jz	rn1
	cpi	'_'
	jnz	cmderr
rn1:	inx	h
	shld	cptr
	lxi	d,FCB2
	call	fillfcb
	jnz	cmderr
	pop	psw		; drives must agree
	mov	b,a
	lda	FCB2
	ora	a
	jz	rn2
	cmp	b
	jz	rn2
	mov	a,b
	ora	a
	jnz	cmderr
	lda	FCB2
	sta	DFCB
rn2:	lda	DFCB
	sta	FCB2
	lxi	d,DFCB		; the new name mustn't exist
	mvi	c,F_SFIRST
	call	sys
	inr	a
	jz	rn3
	lxi	h,mexist
	call	pmsg
	jmp	prompt
rn3:	lxi	h,DFCB		; old at FCB, new at FCB+16
	lxi	d,rntmp
	mvi	b,16
	call	movb
	lxi	h,FCB2
	lxi	d,DFCB
	mvi	b,16
	call	movb
	lxi	h,rntmp
	lxi	d,FCB2
	mvi	b,16
	call	movb
	lxi	d,DFCB
	mvi	c,F_RENAME
	call	sys
	inr	a
	jz	nofile
	jmp	endcmd

; USER n
cuser:	call	number
	cpi	16
	jnc	cmderr
	mov	e,a
	call	setusr
	jmp	endcmd

; number - A = the decimal number at cptr (CY/cmderr if none).
number:	call	skipsp
	shld	cword
	mvi	b,0
	mov	a,m
	sui	'0'
	cpi	10
	jnc	cmderr
nu1:	mov	a,m
	sui	'0'
	cpi	10
	jnc	nu2
	mov	c,a
	mov	a,b		; B = B * 10 + digit
	add	a
	add	a
	add	b
	add	a
	add	c
	mov	b,a
	inx	h
	jmp	nu1
nu2:	shld	cptr
	mov	a,b
	ret

; ---- Running a program ----

; trans - NAME (or d:NAME): NAME.COM, or NAME.ABS through HDOS.COM.
trans:	lxi	h,DFCB+9
	mov	a,m
	cpi	' '
	jnz	cmderr		; no type allowed
	lxi	h,mcom
	call	settyp
	lxi	d,DFCB
	mvi	c,F_OPEN
	call	sys
	inr	a
	jnz	load
	lxi	h,mabs		; NAME.ABS?
	call	settyp
	lxi	d,DFCB
	mvi	c,F_OPEN
	call	sys
	inr	a
	jz	cmderr
	; Run "HDOS d:NAME args": the tail is the command line from the
	; command word on, and the program HDOS.COM on drive A.
	lhld	cword
	shld	cptr0
	mvi	a,1
	sta	hdosrun
	lxi	h,DFCB		; A:HDOS.COM
	mvi	m,1
	inx	h
	lxi	d,mhdos
	xchg
	mvi	b,11
	call	movb
	lxi	d,DFCB
	mvi	c,F_OPEN
	call	sys
	inr	a
	jz	cmderr

; load - the open program at DFCB into 0100H, then FCBs, tail, go.
load:	lxi	h,TPA
ld1:	push	h
	xchg
	mvi	c,F_DMAOFF
	call	sys
	lxi	d,DFCB
	mvi	c,F_READ
	call	sys
	pop	h
	ora	a
	jnz	ld2
	lxi	d,128
	dad	d
	xchg			; up to the shell, or the HDOS
	lhld	BDOS+1		; extension below it
	mvi	l,0
	mov	a,h
	cpi	SHELLB shr 8
	jc	ld1a
	lxi	h,SHELLB
ld1a:	call	cmpde
	xchg
	jnc	ld1
	lxi	h,mbadld
	call	pmsg
	jmp	prompt
ld2:	call	seldsk
	lxi	d,DFCB		; FCB 1 and 2 from the arguments
	call	fillfcb
	lda	DFCB
	push	psw
	lxi	d,FCB2
	call	fillfcb2
	pop	psw
	sta	DFCB
	lhld	cptr0		; the tail: everything after the name
	lxi	d,TBUF+1
	mvi	b,0
	lda	hdosrun		; (for HDOS.COM: " NAME args")
	ora	a
	jz	ld3
	mvi	a,' '
	stax	d
	inx	d
	inr	b
ld3:	mov	a,m
	stax	d
	ora	a
	jz	ld4
	inx	h
	inx	d
	inr	b
	jmp	ld3
ld4:	mov	a,b
	sta	TBUF
	xra	a
	sta	DFCB+32
	call	crlf
	lxi	d,TBUF
	mvi	c,F_DMAOFF
	call	sys
	call	setcdk
	call	TPA		; run it
	lxi	sp,stack	; it returned
	call	setdk
	call	seldsk
	jmp	prompt

; fillfcb2 - fillfcb into the 16 bytes at FCB2 (only the name).
fillfcb2: lxi	d,f2tmp
	call	fillfcb
	lxi	h,f2tmp
	lxi	d,FCB2
	mvi	b,16
	jmp	movb

; settyp - the FCB's type = the 3 chars at HL.
settyp:	lxi	d,DFCB+9
	mvi	b,3
; movb - copy B bytes from HL to DE.
movb:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	movb
	ret

; ---- Disks and users ----

; fcbdk - A = the drive the FCB means.
fcbdk:	lda	DFCB
	dcr	a
	rp
	lda	cdisk
	ret

seldsk:	lda	cdisk
	mov	e,a
	mvi	c,14
	jmp	sys
setusr:	mvi	c,32
	jmp	sys

; setcdk - 0004 = user << 4 + drive.
setcdk:	mvi	e,0FFh
	mvi	c,32
	call	sys
	rlc
	rlc
	rlc
	rlc
	lxi	h,cdisk
	ora	m
	sta	IOCDISK
	ret

; setdk - 0004 = the drive only.
setdk:	lda	cdisk
	sta	IOCDISK
	ret

; ---- Output ----

sys:	jmp	BDOS

putc:	push	b
	push	d
	push	h
	mov	e,a
	mvi	c,C_WRITE
	call	sys
	pop	h
	pop	d
	pop	b
	ret
crlf:	mvi	a,13
	call	putc
	mvi	a,10
	jmp	putc

; pmsg - new line, then the string at HL up to NUL.
pmsg:	call	crlf
pm1:	mov	a,m
	ora	a
	rz
	call	putc
	inx	h
	jmp	pm1

cmpde:	mov	a,h
	cmp	d
	rnz
	mov	a,l
	cmp	e
	ret

mnofil:	db	'NO FILE',0
mall:	db	'ALL (Y/N)?',0
mexist:	db	'FILE EXISTS',0
mnospc:	db	'NO SPACE',0
mrderr:	db	'READ ERROR',0
mbadld:	db	'BAD LOAD',0
mcom:	db	'COM'
mabs:	db	'ABS'
mhdos:	db	'HDOS    COM'


	include	kxload.asm


; ---- Variables ----
submit:	ds	1		; SUBMIT is running
cdisk:	ds	1		; current drive
cptr:	ds	2		; parse position
cptr0:	ds	2		; after the command name
cword:	ds	2		; start of the word being parsed
rntmp	equ	TBUF		; (TBUF is free when these are used)
f2tmp	equ	TBUF+40
qtot:	ds	1		; "?" in the last name
hdosrun: ds	1		; running an .ABS through HDOS.COM
	ds	28		; (programs get 8 levels of it, as on CP/M)
stack	equ	$
	assert	$ <= SHELLB+800h
