; test.inc - helpers for CP/M differential tests.
;
; A test is a .COM program. tests/cpmdiff.sh runs it under Heath CP/M
; and under HCOS and compares what it prints between {{ and }}. Keep
; the output under 20 lines.
;
; Optional header comments read by the harness:
;   ; ARGS: text      command-line arguments
;   ; KEYS: text      typed when WAIT appears (printf %b escapes)
;   ; WAIT: text      default {{

	.8080
	include	cpm.inc

	org	TPA
	jmp	TESTMAIN

; bcall C, DE - call the BDOS keeping BC, DE, HL.
bcall:	push	b
	push	d
	push	h
	call	BDOS
	pop	h
	pop	d
	pop	b
	ret

; PSTR - print the zero-terminated string after the call.
PSTR:	xthl
ps1:	mov	a,m
	inx	h
	ora	a
	jz	ps2
	call	PCHR
	jmp	ps1
ps2:	xthl
	ret

; PCHR - print A. Keeps all registers.
PCHR:	push	psw
	push	b
	push	d
	push	h
	mov	e,a
	mvi	c,C_WRITE
	call	BDOS
	pop	h
	pop	d
	pop	b
	pop	psw
	ret

PNL:	push	psw
	mvi	a,13
	call	PCHR
	mvi	a,10
	call	PCHR
	pop	psw
	ret

; PHEX - A as 2 hex digits; PHEXW - HL as 4. Keep registers.
PHEX:	push	psw
	rrc
	rrc
	rrc
	rrc
	call	pnib
	pop	psw
	push	psw
	call	pnib
	pop	psw
	ret
pnib:	ani	0Fh
	adi	90h
	daa
	aci	40h
	daa
	jmp	PCHR
PHEXW:	push	psw
	mov	a,h
	call	PHEX
	mov	a,l
	call	PHEX
	pop	psw
	ret

; PA - print " A" and A in hex.
PA:	push	psw
	mvi	a,' '
	call	PCHR
	pop	psw
	jmp	PHEX
