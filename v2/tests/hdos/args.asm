; args.asm - command-line arguments are passed below STACK, at SP.
; ARGS: foo  Bar.x=sy1:z

	include	test.inc

TESTMAIN:
	lxi	h,0
	dad	sp
	call	PSTR
	db	'{{SP=',0
	call	PHEXW
	call	PSTR
	db	' [',0
loop:	mov	a,m
	ora	a
	jz	done
	SCALL	.SCOUT
	inx	h
	jmp	loop
done:	call	PSTR
	db	']}}',12Q,0
	xra	a
	SCALL	.EXIT

TESTLEN	equ	$-USERFWA
