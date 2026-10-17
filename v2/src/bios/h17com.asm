; h17com.asm - H17.COM: the H17 driver (h17.asm) for the BIOS's slot,
; in the H17/H37 build booted from the H37. Drives D:-F:.

	.8080
	include	cpm.inc
	include	biosram.inc

tdead	equ	B.TDEAD		; the BIOS's, for a driver in the slot
tpast	equ	B.TPAST
twait	equ	B.TWAIT

	org	TPA
	include	slotldr.inc
msg:	db	'H17 driver loaded: D: E: F:',13,10,'$'

img:
	.phase	SLOTB
	jmp	h17rd		; the slot's entries (biosram.inc)
	jmp	h17wr
	jmp	h17rdy
	jmp	h17op
	jmp	h17tck
	jmp	h17isr
	jmp	h17ini
	assert	$ == SLOTB+3*SLOTN
	include	h17.asm
h17isr:	ei			; (the H17 has no RST 4)
	ret
slend:
	.dephase
	assert	slend <= SLOTB+800h
