; layout.inc - where HCOS v2 lives in memory and on disk
;
; The reserved tracks (3 tracks, sectors 0-29, 7680 bytes) are a memory
; image of SYSB..SYSEND-1: the boot record, the shell, the BDOS and the
; BIOS's code and tables. The H17 boot record reads them all with one
; R.READ. The BIOS's variables and buffers follow, from BIOSRAM up, and
; aren't stored on disk.

SYSB	equ	0D900h		; sector 0 of the disk is loaded here
BOOTB	equ	2280h		; where the ROM loads and runs the boot record
SHELLB	equ	0DA00h		; shell, 2K (entry SHELLB: run the command in
				; its buffer, SHELLB+3: prompt)
BDOSB	equ	0E200h		; BDOS (entry BDOSB+6)
BIOSB	equ	0F000h		; BIOS jump table
SYSEND	equ	0F700h		; end of the reserved tracks' image
SYSLEN	equ	SYSEND-SYSB	; 1E00H: 30 sectors
BIOSLEN	equ	SYSEND-BIOSB	; room for the BIOS's code and tables
BIOSRAM	equ	SYSEND		; BIOS variables, buffers and stack
KXVEC	equ	BDOSB+11h	; the BDOS's hook for the HDOS extension
; The boot record's sector ends with what warm boot checks: the length
; and 16-bit sum of the shell's and the BDOS's code (tools/mksys.py).
SYSTAB	equ	SYSB+0F8h	; shell length, sum, BDOS length, sum

; BIOS entries
B.BOOT	equ	BIOSB
B.WBOOT	equ	BIOSB+3
B.CONST	equ	BIOSB+6
B.CONIN	equ	BIOSB+9
B.CONOUT	equ	BIOSB+12
B.LIST	equ	BIOSB+15
B.PUNCH	equ	BIOSB+18
B.READER	equ	BIOSB+21
B.HOME	equ	BIOSB+24
B.SELDSK	equ	BIOSB+27
B.SETTRK	equ	BIOSB+30
B.SETSEC	equ	BIOSB+33
B.SETDMA	equ	BIOSB+36
B.READ	equ	BIOSB+39
B.WRITE	equ	BIOSB+42
B.LISTST	equ	BIOSB+45
B.SECTRAN	equ	BIOSB+48
; HCOS's own, after CP/M 2.2's 17
B.TICKS	equ	BIOSB+51	; HL = 2 ms ticks since reset

; Hardware (H89)
GPP	equ	0F2h		; 362Q: general purpose port (OP2.CTL), SW501 in
GP.CLI	equ	02h		; 2 ms clock interrupt enable
GP.ORG	equ	20h		; RAM at 0000H-1FFFH
SW.BAU	equ	40h		; SW501: 19200 baud console
CON	equ	0E8h		; 350Q: console 8250
CON.LCR	equ	CON+3
CON.MCR	equ	CON+4
CON.LSR	equ	CON+5
CON.IER	equ	CON+1

; MTR-90 / H17 ROM, while the ROM is in
R.READ	equ	1C3Fh		; HL = sector, DE = buffer, BC = bytes; CY on error
TICCNT	equ	201Bh		; the ROM's 2 ms tick count
