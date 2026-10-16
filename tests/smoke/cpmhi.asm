; cpmhi.asm - CP/M smoke test: print a line and warm boot.

	.8080
	include	cpm.inc

	org	TPA
	lxi	d,msg
	mvi	c,C_WRITESTR
	call	BDOS
	jmp	BOOT

msg:	db	'HCOS CPM SMOKE OK',0dh,0ah,'$'
