; cpm.inc - CP/M 2.2 BDOS interface (DRI CP/M 2.2 Interface Guide)

BOOT	equ	0000h		; warm boot vector
BDOS	equ	0005h		; BDOS entry
DFCB	equ	005Ch		; default FCB
TBUF	equ	0080h		; default DMA buffer / command tail
TPA	equ	0100h		; .COM load and entry address

; BDOS functions (in C)
C_READ	equ	1		; console input with echo
C_WRITE	equ	2		; console output, char in E
L_WRITE	equ	5		; list output, char in E
C_RAWIO	equ	6		; direct console I/O: E=0FFH input/status
C_WRITESTR equ	9		; print string at DE, ends with '$'
C_STAT	equ	11		; console status
DRV_RESET equ	13		; reset disk system
DRV_SEL	equ	14		; select drive E
F_OPEN	equ	15
F_CLOSE	equ	16
F_SFIRST equ	17
F_SNEXT	equ	18
F_DELETE equ	19
F_READ	equ	20		; sequential read
F_WRITE	equ	21		; sequential write
F_MAKE	equ	22
F_RENAME equ	23
DRV_GET	equ	25		; current drive, 0 = A
F_DMAOFF equ	26		; set DMA address to DE
DRV_ALLOC equ	27		; HL = allocation vector
DRV_DPB	equ	31		; HL = disk parameter block
F_READRAND equ	33
F_WRITERAND equ	34
F_SIZE	equ	35		; compute file size into R0-R2

; FCB layout
FCB.DR	equ	0		; drive, 0 = default, 1 = A
FCB.NAME equ	1		; 8 bytes
FCB.TYP	equ	9		; 3 bytes
FCB.EX	equ	12
FCB.S2	equ	14
FCB.RC	equ	15
FCB.CR	equ	32		; current record
FCB.R0	equ	33		; random record, 3 bytes
FCBLEN	equ	36
