; test.inc - helpers for HDOS differential tests.
;
; A test is an .ABS program. tests/difftest.sh runs it on real HDOS 2.0
; and under HDOS.COM on CP/M and compares what it prints between the
; {{ and }} markers, so a test prints only lines it expects to match.
; Keep the output under 20 lines: the harness reads the final screen.
;
; Optional header comments read by the harness:
;   ; ARGS: text      command-line arguments
;   ; KEYS: text      typed once {{ appears; printf %b escapes such as
;                     \r, \b, \003 and \177 give control keys
;   ; WAIT: text      type the KEYS when this appears instead of {{

	.8080
	include	hdos.inc

	org	USERFWA-8
	ABSHDR	USERFWA,TESTLEN,TESTMAIN

; Print the zero-terminated string that follows the call:
;	call	PSTR
;	db	'text',0
; Preserves all but A and flags.
PSTR:	xthl
PSTR1:	mov	a,m
	inx	h
	ora	a
	jz	PSTR2
	push	h
	SCALL	.SCOUT
	pop	h
	jmp	PSTR1
PSTR2:	xthl
	ret

; Print A as two hex digits. Preserves all but A and flags.
PHEX:	push	psw
	rrc
	rrc
	rrc
	rrc
	call	PNIB
	pop	psw
PNIB:	ani	0fh
	adi	90h
	daa
	aci	40h
	daa
	SCALL	.SCOUT
	ret

; Print HL as four hex digits.
PHEXW:	mov	a,h
	call	PHEX
	mov	a,l
	jmp	PHEX

; Print the carry as " C=x", and A as " A=hh" only when carry is set
; (after a good SCALL, A holds whatever HDOS left in it).
PRES:	push	psw
	call	PSTR
	db	' C=',0
	pop	psw
	push	psw
	mvi	a,'0'
	aci	0
	SCALL	.SCOUT
	pop	psw
	rnc
	push	psw
	call	PSTR
	db	' A=',0
	pop	psw
	jmp	PHEX

PNL:	mvi	a,12Q
	SCALL	.SCOUT
	ret
