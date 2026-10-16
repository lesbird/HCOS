; hcos.inc - addresses shared by the HCOS kernel parts (64K Heath CP/M
; layout)

KXBASE	equ	0C300h		; kernel extension HCOS.SYS (TPA top)
KXVEC	equ	0E211h		; BDOS's hook vector (3 bytes, a JMP)
KXSIGO	equ	3		; signature "HCKX" at KXBASE+3
KX.HOOK	equ	KXBASE+7	; JMP kxhook
KX.RST	equ	KXBASE+10	; JMP kxreset
KX.VER	equ	KXBASE+13	; version byte: must be KXVER
KXVER	equ	1
KXEND	equ	0D980h		; must end below what warm boot loads
