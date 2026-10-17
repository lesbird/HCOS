; console.asm - console SCALLs: .SCIN .SCOUT .PRINT .CONSL .CLRCO
;
; Follows the HDOS 2.0 resident console code. HDOS reads the keyboard
; on interrupts; here kpoll reads CP/M's console (BDOS 6) at every
; SCALL and does the same work: type-ahead, line editing and echo,
; ^A/^B/^C handlers, ^O, ^S/^Q. Console state lives in the real
; S.CSLMD..S.CONFL cells, since programs poke them directly.
;
; Output goes out through BDOS 6 so CP/M does not expand tabs or
; act on ^S itself.

NL	equ	0Ah
CR	equ	0Dh
BS	equ	08h
TAB	equ	09h
FF	equ	0Ch
BEL	equ	07h
RUB	equ	7Fh
CTLD	equ	04h
CTLO	equ	0Fh
CTLP	equ	10h
CTLQ	equ	11h
CTLS	equ	13h
CTLU	equ	15h
CTLZ	equ	1Ah
KSIZE	equ	128		; type-ahead size (power of 2)

cinit:	lxi	h,0
	shld	kin			; kin, kout
	xra	a
	sta	klines
	ret

; ---- .SCIN: A = next char, NC; CY if none. Keeps BC, DE, HL. ----
sscin:	push	h
	push	d
	push	b
	call	kpoll
	lda	S.CSLMD
	ani	CSL.CHR
	jnz	si.chr
	lda	klines			; line mode: only whole lines
	ora	a
	jz	si.none
si.chr:	lhld	kin			; L = kin, H = kout
	mov	a,l
	cmp	h
	jz	si.none
	mov	e,h			; A = kbuf[kout]
	mvi	d,0
	lhld	pkbuf
	dad	d
	mov	b,m
	mov	a,e
	inr	a
	ani	KSIZE-1
	sta	kout
	mov	a,b
	cpi	NL
	jz	si.eol
	cpi	CTLD
	jnz	si.ok
si.eol:	lda	klines
	ora	a
	jz	si.eol1
	dcr	a
	sta	klines
si.eol1: mov	a,b
si.ok:	ora	a			; NC
	jmp	popbdh
si.none: stc
popbdh:	pop	b
	pop	d
	pop	h
	ret

; ---- .SCOUT: A = char. Keeps every register and the flags. ----
sscout:	push	psw
	push	b
	push	d
	push	h
	call	cout
	pop	h
	pop	d
	pop	b
	pop	psw
	ret

; ---- .PRINT: HL -> text, last char has bit 7. Exit HL past it. ----
; Same loop as HDOS 2.0, so the flags come back the same (CY set).
sprint:	push	b
	push	d
spr1:	mov	a,m
	ani	7Fh
	push	h
	call	cout
	pop	h
	cmp	m
	inx	h
	jz	spr1
	pop	d
	pop	b
	ret

; ---- .CONSL: A = index 0-4 of S.CSLMD.., B = new bits, C = mask of
; bits to change. Exit A = new value. ----
sconsl:	cpi	5
	jc	sco1
	mvi	a,EC.ILR
	stc
	ret
sco1:	lxi	h,S.CSLMD
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	mov	a,c
	ana	b
	mov	b,a
	mov	a,c
	cma
	di
	ana	m
	ora	b
	mov	m,a
	ei
	ora	a			; NC
	ret

; ---- .CLRCO: empty the type-ahead, clear ^O and ^S. ----
sclrco:	call	cinit
	xra	a
	sta	S.CONFL
	ret

; ---- .VERS: A = 20H (HDOS 2.0), NC. ----
svers:	mvi	a,20h
	ora	a
	ret

; ---- .CTLC: A = 1, 2 or 3 (^A, ^B, ^C), HL = handler or 0. ----
sctlc:	dcr	a
	cpi	3
	jc	sct1
	mvi	a,EC.ILC
	stc
	ret
sct1:	xchg				; DE = handler
	lxi	h,S.CCTAB
	add	a
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	mov	m,e
	inx	h
	mov	m,d
	xchg
	xra	a
	ret

; ---- kpoll: take what has been typed into the type-ahead. ----
; Uses all registers.
kpoll:	mvi	c,C_RAWIO
	mvi	e,0FFh
	call	BDOS
	ora	a
	rz
	call	kchar
	jmp	kpoll

; kchar - process one typed character in A.
kchar:	ani	7Fh
	mov	b,a
	lda	S.CSLMD
	ani	CSL.RAW
	mov	a,b
	jnz	kstore			; raw: store anything as typed
	ora	a
	rz				; NUL: dropped
	cpi	NL
	rz				; typed LF: dropped
	cpi	CR
	jnz	kc1
	mvi	a,NL			; CR is stored as NL
	jmp	kline
kc1:	cpi	4
	jc	kctl			; ^A ^B ^C
	cpi	CTLZ
	jz	kctlz
	sta	klast
	cpi	CTLO
	jz	kctlo
	cpi	CTLS
	jz	kctls
	cpi	CTLQ
	jz	kctlq
	cpi	CTLP
	jz	kctlp
	mov	b,a			; line editing, line mode only
	lda	S.CSLMD
	ani	CSL.CHR
	mov	a,b
	jnz	kline
	cpi	RUB
	jz	krub
	cpi	BS
	jnz	kc2
	lda	S.CONTY
	ani	CTP.BKM
	mvi	a,BS
	jnz	krub
kc2:	push	psw			; a run of "/" rubouts ends
	lda	kslash
	ora	a
	jz	kc3
	xra	a
	sta	kslash
	mvi	a,'/'
	call	coutnp
kc3:	pop	psw
	cpi	CTLU
	jz	kctlu
kline:	cpi	'a'			; map lower case if asked
	jc	kstore
	cpi	'z'+1
	jnc	kstore
	mov	b,a
	lda	S.CONTY
	ani	CTP.MLI
	mov	a,b
	jz	kstore
	sui	20h

; kstore - put A in the type-ahead and echo it.
kstore:	mov	b,a
	lhld	kin			; L = kin, H = kout
	mov	a,l
	inr	a
	ani	KSIZE-1
	cmp	h
	jnz	ks1
	mvi	a,BEL			; full: ring the bell, drop it
	jmp	coutnp
ks1:	sta	kin
	mvi	h,0
	xchg
	lhld	pkbuf
	dad	d
	mov	m,b
	mov	a,b
	cpi	NL
	jz	ks2
	cpi	CTLD
	jnz	kecho
ks2:	lxi	h,klines
	inr	m
kecho:	lda	S.CSLMD			; echo unless suppressed
	ani	CSL.ECH
	rnz
	mov	a,b
	jmp	coutnp

; ^A, ^B, ^C: if the program has a handler, make it the pending abort
; address; it runs when the current SCALL returns. Otherwise ignored.
kctl:	dcr	a
	add	a
	lxi	h,S.CCTAB+1
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	mov	a,m			; high byte 0: no handler
	ora	a
	rz
	sta	S.CAADR+1
	dcx	h
	mov	a,m
	sta	S.CAADR
	ret

kctlo:	lda	S.CONFL
	xri	CO.FLG
	sta	S.CONFL
	ret
kctls:	lda	S.CONFL
	ori	CS.FLG
	sta	S.CONFL
	ret
kctlq:	lda	S.CONFL
	ani	0FFh-CS.FLG
	sta	S.CONFL
	ret
kctlp:	lda	S.CONFL
	ani	0FFh-CO.FLG
	sta	S.CONFL
	ret

; Rubout: delete the last char of the line being typed, if any.
; HDOS 2.0 echoes rubouts and ^U even with echo suppressed.
krub:	call	kdel
	rc
	mov	b,a			; B = deleted char
	lda	S.CONTY
	ani	CTP.BKS
	jz	krub1
	mvi	a,BS			; BS SP BS
	call	coutnp
	mvi	a,' '
	call	coutnp
	mvi	a,BS
	jmp	coutnp
krub1:	lda	kslash			; or "/" (once per run) and the char
	ora	a
	jnz	krub2
	inr	a
	sta	kslash
	mvi	a,'/'
	push	b
	call	coutnp
	pop	b
krub2:	mov	a,b
	jmp	coutnp

; ^Z: "^Z?"; a second ^Z in a row aborts the program.
kctlz:	mvi	a,'^'
	call	coutnp
	mvi	a,'Z'
	call	coutnp
	lda	klast
	cpi	CTLZ
	jz	kctlz2
	mvi	a,CTLZ
	sta	klast
	mvi	a,'?'
	jmp	coutnp
kctlz2:	call	kctlq			; also undoes ^S
	lxi	h,S.EXITA		; pending abort: exit
	shld	S.CAADR
	ret

; ^U: delete the whole line being typed.
kctlu:	call	kdel
	jnc	kctlu
	mvi	a,'^'
	call	coutnp
	mvi	a,'U'
	call	coutnp
	mvi	a,NL
	jmp	coutnp

; kdel - remove the last char typed unless the buffer is empty or it
; ends a line. Returns A = the char, or CY if none.
kdel:	lhld	kin
	mov	a,l
	cmp	h
	stc
	rz
	dcr	a
	ani	KSIZE-1
	mov	c,a
	mov	e,a
	mvi	d,0
	lhld	pkbuf
	dad	d
	mov	a,m
	cpi	NL
	stc
	rz
	cpi	CTLD
	stc
	rz
	mov	b,a
	mov	a,c
	sta	kin
	mov	a,b
	ora	a
	ret

; ---- cout: send A to the console the way HDOS 2.0 .SCOUT does. ----
; Uses all registers.
cout:	push	psw
	call	kpoll			; watch for ^S, ^O, ^C while printing
co.wt:	lda	S.CONFL
	ani	CS.FLG
	jz	co.go
	call	kpoll			; stopped by ^S until ^Q
	jmp	co.wt
co.go:	lda	S.CONFL
	ani	CO.FLG
	jz	co.go1
	pop	psw			; ^O: output suppressed
	ret
co.go1:	pop	psw

; coutnp - cout without the keyboard, ^S and ^O, for echo.
coutnp:	ani	7Fh
	cpi	60h			; map lower case if asked
	jc	co1
	mov	b,a
	lda	S.CONTY
	ani	CTP.MLO
	mov	a,b
	jz	co1
	sui	20h
co1:	cpi	' '
	jnc	coprt
	cpi	NL
	jz	conl
	cpi	CR
	jz	cocr
	cpi	TAB
	jz	cotab
	cpi	BS
	jz	cobs
	cpi	FF
	jnz	cosend			; other controls: as is
	mov	b,a
	lda	S.CONTY
	ani	CTP.FF
	mov	a,b
	jnz	cosend
	mvi	b,10			; FF the terminal can't do: 10 LFs
coff:	push	b
	mvi	a,NL
	call	co.raw
	pop	b
	dcr	b
	jnz	coff
	ret

conl:	mov	b,a
	lda	S.CSLMD
	ani	CSL.RAW
	mov	a,b
	jnz	cosend			; raw: bare LF
	mvi	a,1
	sta	S.CUSOR
	mvi	a,CR
	call	co.raw
	mvi	a,NL
	jmp	co.raw
cocr:	mvi	a,1
	sta	S.CUSOR
	mvi	a,CR
	jmp	co.raw
cobs:	lda	S.CUSOR
	dcr	a
	jz	cobs1
	sta	S.CUSOR
cobs1:	mvi	a,BS
	jmp	co.raw
cotab:	lda	S.CONTY
	ani	CTP.TAB
	jz	cotab1
	lda	S.CUSOR			; terminal tabs: just track it
	dcr	a
	ori	7
	adi	2
	sta	S.CUSOR
	mvi	a,TAB
	jmp	co.raw
cotab1:	mvi	a,' '			; spaces to the next tab stop
	call	coprt
	lda	S.CUSOR
	dcr	a
	ani	7
	jnz	cotab1
	ret

coprt:	mov	b,a			; printable: wrap past the width
	lda	S.CONWI
	mov	c,a
	lda	S.CUSOR
	cmp	c
	jc	copr1
	jz	copr1
	push	b
	mvi	a,CR
	call	co.raw
	mvi	a,NL
	call	co.raw
	pop	b
	mvi	a,1
copr1:	inr	a
	sta	S.CUSOR
	mov	a,b
	jmp	co.raw

cosend:
co.raw:	mov	e,a			; raw output, A preserved
	push	psw
	mvi	c,C_RAWIO
	call	BDOS
	pop	psw
	ret

kin:	db	0			; type-ahead write index
kout:	db	0			; read index (must follow kin)
klines:	db	0			; complete lines in the type-ahead
klast:	db	0			; last char typed (for ^Z ^Z)
kslash:	db	0			; in a run of "/" rubout echoes
