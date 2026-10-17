; h37com.asm - H37.COM: the H37 driver (h37.asm) for the BIOS's slot,
; in the H17/H37 build booted from the H17. Drives D:-F:.

	.8080
	include	cpm.inc
	include	biosram.inc

tdead	equ	B.TDEAD		; the BIOS's, for a driver in the slot
tpast	equ	B.TPAST
twait	equ	B.TWAIT

	org	TPA
	include	slotldr.inc
msg:	db	'H37 driver loaded: D: E: F:',13,10,'$'

img:
	.phase	SLOTB
	jmp	dkrd		; the slot's entries (biosram.inc)
	jmp	dkwr
	jmp	dkrdy
	jmp	dkop
	jmp	dktck
	jmp	dkisr
	jmp	dkini
	assert	$ == SLOTB+3*SLOTN
	include	h37.asm
slend:
	.dephase
	assert	slend <= SLOTB+800h
