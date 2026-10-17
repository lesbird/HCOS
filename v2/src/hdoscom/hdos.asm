; hdos.asm - HDOS.COM: run HDOS 2.0 .ABS programs natively on HCOS v2
;
;	A>HDOS [/T] [/C] PROG [args]
;
; The program runs with the monitor ROM and H17 ROM in at 0000H-1FFFH, as
; on HDOS (H-mode), so it uses the ROM's own routines. Each SCALL maps RAM
; in, so that HDOS.COM's code under the ROM and the CP/M BDOS and BIOS can
; carry it out, and the ROM in again. (Version 1 ran HDOS programs with
; RAM at 0000H by default, C-mode. HCOS v2 always uses H-mode.)
;
; The RAM under the H17 ROM's utility routines (1830H-1991H) still holds
; an exact copy of them (romlib.asm). The ROM's routines make SCALLs with
; the function byte inline, and the dispatcher reads it with RAM in.
; /T traces every SCALL on the console: its number, in octal.
;
; Loads PROG.ABS at the address in its header, builds the HDOS system
; area at 2000H-227FH, points RST 7 at the SCALL dispatcher and runs
; the program. SCALLs are carried out with BDOS calls. Any exit path
; puts page zero back and warm boots.
;
; HDOS.COM itself lives below 2000H, out of the way of HDOS programs.
;
; From version 1 (phases 1-6 there). The shell runs NAME.ABS with it.

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

; hisys.asm, assembled for the high buffers; start-up copies it there.
systpl:
	.phase	HIFIX+HI.SYS
	include	hisys.asm
	.dephase
SYSTLEN	equ	$-systpl
	assert	SYSTLEN <= 256

	assert	$ <= ROMLIB		; code must end below the ROM library
	include	romlib.asm		; H17 ROM routines, 1830H-1991H

; ---- High buffers: just below HCOS v2's BDOS ----
; At a fixed address, so that hisys.asm can be assembled for it. The
; HDOS extension, if it is in, is moved aside (see start).
V2BDOS	equ	0E200h			; (src/inc/layout.inc: BDOSB,
V2KXVEC	equ	V2BDOS+11h		; KXVEC, KXBASE+KXSIGO, KXNEED)
V2KXSIG	equ	0C303h
V2KXNEED equ	V2BDOS+14h
HI.GRT	equ	0			; GRT of each unit, 256 each (page
					; aligned: HIFIX is)
HI.SCR	equ	HI.GRT+NUNIT*256	; system scratch area (S.SCR), 512
HI.SEC	equ	HI.SCR+512		; sector / directory block buffer, 512
HI.KBUF	equ	HI.SEC+512		; type-ahead
HI.CHT	equ	HI.KBUF+KSIZE		; channel table, channels -1..5
HI.CMD	equ	HI.CHT+NCHAN*CHLEN	; copy of the command tail, 129
HI.SYS	equ	HI.CMD+129		; hisys.asm, 256
HISIZE	equ	(HI.SYS+256+255) and 0FF00h
HIFIX	equ	V2BDOS-HISIZE

; ---- More code, after the ROM library ----
	org	ROMLIBE
	include	syndir.asm
	include	hdoswr.asm
	include	systab.asm


; ---- Buffers (not stored in HDOS.COM) ----
errfcb	equ	DFCB			; CP/M's default FCB is free once
tmpfcb2	equ	DFCB			; HDOS.COM runs; .ERROR and the
					; others never overlap
tmpfcb:	ds	FCBLEN
	ds	96			; (BDOS calls use the BDOS's stack)
hcstk	equ	$			; HDOS.COM's own stack

HCEND	equ	$
	assert	HCEND <= 2000h		; must stay below the system area
