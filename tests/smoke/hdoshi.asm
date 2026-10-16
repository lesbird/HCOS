; hdoshi.asm - HDOS smoke test: print a line and exit.

	.8080
	include	hdos.inc

	org	USERFWA-8
	ABSHDR	USERFWA,LEN,start

start:	lxi	h,msg
	SCALL	.PRINT
	xra	a
	SCALL	.EXIT

msg:	db	'HCOS HDOS SMOKE O','K'+200Q
LEN	equ	$-USERFWA
