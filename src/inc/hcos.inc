; hcos.inc - addresses shared by the HCOS kernel parts
;
; Everything follows from BIOSB, the Heath BIOS's base, in the build's
; target.inc: F000H on 64K H17 CP/M, E800H on 64K H17/H37 CP/M (its
; bigger BIOS moves the rest down 800H).

	include	target.inc

BDOSB	equ	BIOSB-0E00h	; BDOS (entry BDOSB+6)
CCPB	equ	BDOSB-0800h	; CCP / HCCP
LOADB	equ	CCPB-80h	; warm boot loads LOADB..LOADEND-1
LOADEND	equ	BIOSB-80h
KXEND	equ	LOADB		; the extension ends below that
KXSIZE	equ	1600h
KXBASE	equ	(KXEND and 0FF00h)-KXSIZE ; HCOS.SYS (the TPA top)
KXVEC	equ	BDOSB+11h	; BDOS's hook vector (3 bytes, a JMP)
KXSIGO	equ	3		; signature "HCKX" at KXBASE+3
KX.HOOK	equ	KXBASE+7	; JMP kxhook
KX.RST	equ	KXBASE+10	; JMP kxreset
KX.VER	equ	KXBASE+13	; version byte: must be KXVER
KXVER	equ	1
