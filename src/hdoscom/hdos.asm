; hdos.asm - HDOS.COM: run HDOS 2.0 .ABS programs under CP/M 2.2
;
;	A>HDOS [/T] PROG [args]
;
; /T traces every SCALL on the console: [fff A=aa] in octal and hex.
;
; Loads PROG.ABS at the address in its header, builds the HDOS system
; area at 2000H-227FH, points RST 7 at the SCALL dispatcher and runs
; the program. SCALLs are carried out with BDOS calls. Any exit path
; puts page zero back and warm boots.
;
; HDOS.COM itself lives below 2000H, out of the way of HDOS programs.
;
; Phase 1 of HCOS (docs/ARCHITECTURE.md section 13).

	.8080
	include	cpm.inc
	include	hdos.inc

KX	equ	0			; (not the kernel extension)
HDATE	equ	S.DATC			; date for new HDOS files

	org	TPA
	jmp	start

	include	scall.asm
	include	console.asm
	include	files.asm
	include	loader.asm
	include	sysarea.asm
	include	main.asm
	include	bios.asm
	include	hdosfs.asm
	include	hdosdir.asm

	assert	$ <= ROMLIB		; code must end below the ROM library
	include	romlib.asm		; H17 ROM routines, 1830H-1991H

; ---- High buffers: just below the CP/M BDOS, found at run time ----
HI.GRT	equ	0			; GRT of each unit, 256 each (page
					; aligned: hibase is)
HI.SCR	equ	HI.GRT+NUNIT*256	; system scratch area (S.SCR), 512
HI.SEC	equ	HI.SCR+512		; sector / directory block buffer, 512
HI.KBUF	equ	HI.SEC+512		; type-ahead
HI.CHT	equ	HI.KBUF+KSIZE		; channel table, channels -1..5
HI.CMD	equ	HI.CHT+NCHAN*CHLEN	; copy of the command tail, 129
HISIZE	equ	(HI.CMD+129+255) and 0FF00h

; ---- More code, after the ROM library ----
	org	ROMLIBE
	include	syndir.asm
	include	hdoswr.asm

; ---- Buffers (not stored in HDOS.COM) ----
errfcb:	ds	FCBLEN
tmpfcb:	ds	FCBLEN
tmpfcb2: ds	FCBLEN
	ds	128
hcstk	equ	$			; HDOS.COM's own stack

HCEND	equ	$
	assert	HCEND <= 2000h		; must stay below the system area
