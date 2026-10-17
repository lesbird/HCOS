; h17boot.asm - HCOS v2 boot record for the H17 (sector 0, track 0)
;
; MTR-90 reads sectors 0-8 to 2280H and jumps here with the ROM in,
; interrupts on, SP = 2280H and the boot unit in 2131H. This reads all
; of the reserved tracks to SYSB with the ROM's R.READ, as Heath's CP/M
; boot record does, and starts the BIOS's cold boot with interrupts off
; and the ROM still in. R.READ needs the ROM's clock, so interrupts stay
; on until it returns, and nothing here HALTs (the ROM's clock takes a
; HALT as a drop to the monitor).

	.8080
	include	layout.inc

	org	BOOTB

	jmp	start
	ds	1Ah		; 03H-1CH: the disk's label (kept by mksys.py)

start:	lxi	h,0		; sector 0 of track 0
	lxi	d,SYSB
	lxi	b,SYSLEN
	call	R.READ
	jc	error
	di
	jmp	B.BOOT

error:	lxi	h,emsg
eloop:	in	CON.LSR
	ani	20h
	jz	eloop
	mov	a,m
	ora	a
	jz	0		; back to the monitor
	out	CON
	inx	h
	jmp	eloop

emsg:	db	0dh,0ah,'?HCOS boot error',0dh,0ah,0

	assert	$ <= BOOTB+0F8h	; (SYSTAB follows)
