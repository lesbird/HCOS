; scall.asm - SCALL dispatcher
;
; A program does RST 7 followed by a function byte. RST 7 lands at
; 0038H, which jumps through the RAM vector slot at .UIVEC+18 (as the
; HDOS ROM does) to scdisp. The handler is entered with the program's
; A, BC, DE, HL as they were at the SCALL, running on HDOS.COM's own
; stack, and returns its results in the same registers and flags.
; Errors: carry set, A = EC.* code.

scdisp:	sta	sca			; save A and HL
	shld	schl
	pop	h			; HL -> function byte
	mov	a,m
	inx	h
	push	h			; return past it
	lxi	h,0			; switch to our stack
	dad	sp
	shld	scsp
	lxi	sp,hcstk

	; Find the handler: functions 000-013 index scr, 040-062 index
	; sco, anything else is illegal.
	sta	scfn
	sta	S.CODE
	lda	sca
	sta	S.CACC
	lda	trace
	ora	a
	cnz	sctrace
	lda	scfn
	lxi	h,scr
	cpi	.CRC16+1
	jc	sc1
	cpi	.MOUNT			; mount group: one handler
	jc	sc0
	cpi	.DAD+1
	jnc	scbad
	lxi	h,smount
	jmp	scgo
sc0:	sui	.LINK
	jc	scbad
	lxi	h,sco
	cpi	.LOADD-.LINK+1
	jnc	scbad
sc1:	add	a			; HL -> table entry
	add	l
	mov	l,a
	mvi	a,0
	adc	h
	mov	h,a
	mov	a,m			; HL = handler
	inx	h
	mov	h,m
	mov	l,a
scgo:	shld	schand			; HL = handler
	lxi	h,scret			; it returns to scret
	push	h
	lhld	schand
	push	h
	lhld	schl
	lda	sca
	ret				; to the handler

; The handler's RET comes here. A, flags, BC, DE, HL pass through.
scret:	shld	schl
	push	psw			; catch keys typed during the call
	push	b
	push	d
	call	kpoll
	pop	d
	pop	b
	pop	psw
	lhld	scsp			; back to the program's stack
	sphl
	push	psw
	lda	S.CAADR+1		; ^A/^B/^C handler pending?
	ora	a
	jnz	scabt
	pop	psw
	lhld	schl
	jmp	TROUT			; (H-mode: ROM in again)

; Run the pending handler, as HDOS's CPA does. It is entered with
; A = 1 and the program's BC, DE, HL; on its stack are a return
; address that resumes the program, the program's PSW and the address
; the program was at.
scabt:	lhld	S.CAADR
	shld	schand
	xra	a
	sta	S.CAADR+1
	lxi	h,TRRES			; (resumes the program)
	push	h
	lhld	schand
	push	h
	lhld	schl
	mvi	a,1
	jmp	TROUT			; to the handler

scbad:	lxi	h,scill			; illegal function
	jmp	scgo

scill:	mvi	a,EC.ILC
	stc
	ret

; .LOADO: A = overlay 0 or 1. Everything is resident already.
sloado:	cpi	2
	mvi	a,EC.IOI
	cmc
	rc
	xra	a
	ret

; .MOUNT .DMOUN .MONMS .DMNMS .RESET .RESNMS .DAD: disks may have been
; changed. Make CP/M log them in again and look at each one afresh.
smount:	mvi	c,DRV_GET
	call	BDOS
	push	psw
	mvi	c,DRV_RESET
	call	BDOS
	pop	psw
	mov	e,a
	mvi	c,DRV_SEL
	call	BDOS
	call	uinit
	xra	a
	sta	rsseen			; (and select them as new)
	ret

; Not implemented yet: say so on the console once per function, then
; fail with EC.ILR so the program can carry on.
scnyi:	push	h
	push	d
	push	b
	lxi	d,mnyi
	mvi	c,C_WRITESTR
	call	BDOS
	lda	scfn
	call	phexo			; function number in octal
	lxi	d,mcrlf
	mvi	c,C_WRITESTR
	call	BDOS
	pop	b
	pop	d
	pop	h
	mvi	a,EC.ILR
	stc
	ret

mnyi:	db	0dh,0ah,'HDOS.COM: no SCALL $'
mcrlf:	db	0dh,0ah,'$'

; Resident functions 000-013.
scr:	dw	sexit			; .EXIT
	dw	sscin			; .SCIN
	dw	sscout			; .SCOUT
	dw	sprint			; .PRINT
	dw	sread			; .READ
	dw	swrite			; .WRITE
	dw	sconsl			; .CONSL
	dw	sclrco			; .CLRCO
	dw	sloado			; .LOADO
	dw	svers			; .VERS
	dw	sgda			; .GDA (3.0)
	dw	scrc16			; .CRC16 (3.0)

; Overlay 0 functions 040-062.
sco:	dw	slink			; .LINK
	dw	sctlc			; .CTLC
	dw	sopenr			; .OPENR
	dw	sopenw			; .OPENW
	dw	sopenu			; .OPENU
	dw	sopenc			; .OPENC
	dw	sclose			; .CLOSE
	dw	sposit			; .POSIT
	dw	sdelet			; .DELET
	dw	srenam			; .RENAM
	dw	ssettp			; .SETTP
	dw	sdecod			; .DECODE
	dw	sname			; .NAME
	dw	sclear			; .CLEAR
	dw	sclra			; .CLEARA
	dw	serror			; .ERROR
	dw	scnyi			; .CHFLG
	dw	scnyi			; .DISMT
	dw	scnyi			; .LOADD

sca:	db	0			; A at the SCALL
schl:	dw	0			; HL at the SCALL
scsp:	dw	0			; program's SP
scfn:	db	0			; function number
schand:	dw	0			; handler address
