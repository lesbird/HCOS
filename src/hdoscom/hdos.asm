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

	org	TPA
	jmp	start

	include	scall.asm
	include	console.asm
	include	files.asm
	include	loader.asm
	include	sysarea.asm
	include	main.asm

	assert	$ <= ROMLIB		; code must end below the ROM library
	include	romlib.asm		; H17 ROM routines, 1830H-1991H

; ---- Buffers, after the ROM library (not stored in HDOS.COM) ----
	org	ROMLIBE
cmdbuf:	ds	129			; copy of the command tail
sscr:	ds	512			; system scratch area (S.SCR)
kbuf:	ds	KSIZE			; type-ahead
chtab:	ds	NCHAN*CHLEN		; channels -1..5
ldfcb:	ds	FCBLEN			; program file
errfcb:	ds	FCBLEN
tmpfcb:	ds	FCBLEN
tmpfcb2: ds	FCBLEN
	ds	128
hcstk	equ	$			; HDOS.COM's own stack

HCEND	equ	$
	assert	HCEND <= 2000h		; must stay below the system area
