; layout.inc - where HCOS v2 lives in memory and on disk
;
; The reserved tracks (3 tracks, sectors 0-29, 7680 bytes) are a memory
; image of SYSB..SYSEND-1: the boot record, the shell, the BDOS and the
; BIOS's code and tables. The H17 boot record reads them all with one
; R.READ. The BIOS's variables and buffers follow, from BIOSRAM up, and
; aren't stored on disk.
;
; Everything follows from BIOSB, the BIOS's base, in the build's
; target.inc: F000H for the H17 build (a 56K TPA), E800H for the H17/H37
; build (54K; its BIOS has 2K more RAM, for the second driver).

	include	target.inc

SYSB	equ	BIOSB-1700h	; sector 0 of the disk is loaded here
BOOTB	equ	2280h		; where the ROM loads and runs the boot record
SHELLB	equ	BIOSB-1600h	; shell, 2K (entry SHELLB: run the command in
				; its buffer, SHELLB+3: prompt)
BDOSB	equ	BIOSB-0E00h	; BDOS (entry BDOSB+6)
SYSEND	equ	BIOSB+700h	; end of the reserved tracks' image
BIOSCB	equ	BIOSB-0E0h	; the BIOS's cold boot: the end of the BDOS's
				; space, which the BDOS doesn't use
SYSLEN	equ	SYSEND-SYSB	; 1E00H: 30 sectors
BIOSLEN	equ	SYSEND-BIOSB	; room for the BIOS's code and tables
BIOSRAM	equ	SYSEND		; BIOS variables, buffers and stack
KXVEC	equ	BDOSB+11h	; the BDOS's hook for the HDOS extension
KXNEED	equ	BDOSB+14h	; set by the BDOS: an HDOS disk, no extension

; Warm boot checks the shell's and the BDOS's code by their 16-bit sums,
; from SHSUMB and BDSUMB to the end of the code: past what changes as
; they run (the shell's command buffer; the BDOS's error vectors, which
; programs may patch, its hook and KXNEED). The boot record's sector
; ends with the lengths and sums (tools/mksys.py).
SHSUMB	equ	SHELLB+0AAh	; (after the buffer and $$$.SUB's FCB)
BDSUMB	equ	BDOSB+15h
SYSTAB	equ	SYSB+0F8h	; shell length, sum, BDOS length, sum

; The HDOS extension, HDOSFS.SYS: loaded by the shell below itself when
; an HDOS disk is in use. It holds the HDOS file system, which CP/M
; programs then use through the BDOS's hook. 0006H points at it then.
KXEND	equ	SHELLB		; (D900H-D9FFH is free after the cold boot)
KXSIZE	equ	1700h
KXBASE	equ	KXEND-KXSIZE
KXSIGO	equ	3		; signature "HCKX" at KXBASE+3
KX.HOOK	equ	KXBASE+7	; JMP kxhook
KX.RST	equ	KXBASE+10	; JMP kxboot: reset, hook, TPA top
KX.VER	equ	KXBASE+13	; version byte: must be KXVER
KXVER	equ	2
KX.LEN	equ	KXBASE+14	; its code's length

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
; With the ROM in (HDOS programs), interrupts come through the ROM's
; RAM vector slots at 201FH up. These two serve them from there:
B.CONINT equ	BIOSB+54	; the console's receive interrupt (EI; RET)
B.TICKR	equ	BIOSB+57	; the ROM's clock hook: count a tick (RET)
; A physical sector, for the HDOS file system: A = 0 read, 1 write; C =
; drive, B = track, E = sector 0-9 (as on the disk), HL = 256 bytes. A =
; 0, or 1 and CY on an error. The BDOS's selection isn't changed.
B.PHYS	equ	BIOSB+60

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
