; hdos.inc - HDOS 2.0 program interface
;
; Sources: HDOS 3.0 HOSDEF/ESVAL/ECDEF/HOSEQU decks (mgarlanger/asmx,
; testHdos/source/acm), checked against HDOS 2.0 running in the H89
; emulator. 3.0-only additions are noted.
;
; Heath listings write addresses in split octal (high byte.low byte):
; 2280H is 042.200 (042200A), which is NOT 042200Q (that is 4480H).

; SCALL: RST 7 followed by an inline function byte.
SYSCALL	equ	377Q
SCALL	macro	func
	db	SYSCALL,func
	endm

; ---- System calls (HOSDEF) ----

; Resident
.EXIT	equ	000Q
.SCIN	equ	001Q
.SCOUT	equ	002Q
.PRINT	equ	003Q
.READ	equ	004Q
.WRITE	equ	005Q
.CONSL	equ	006Q
.CLRCO	equ	007Q
.LOADO	equ	010Q
.VERS	equ	011Q
.GDA	equ	012Q		; 3.0
.CRC16	equ	013Q		; 3.0

; HDOSOVL0.SYS
.LINK	equ	040Q
.CTLC	equ	041Q
.OPENR	equ	042Q
.OPENW	equ	043Q
.OPENU	equ	044Q
.OPENC	equ	045Q
.CLOSE	equ	046Q
.POSIT	equ	047Q
.DELET	equ	050Q
.RENAM	equ	051Q
.SETTP	equ	052Q
.DECODE	equ	053Q
.NAME	equ	054Q
.CLEAR	equ	055Q
.CLEARA	equ	056Q
.ERROR	equ	057Q
.CHFLG	equ	060Q
.DISMT	equ	061Q
.LOADD	equ	062Q

; HDOSOVL1.SYS
.MOUNT	equ	200Q
.DMOUN	equ	201Q
.MONMS	equ	202Q
.DMNMS	equ	203Q
.RESET	equ	204Q
.RESNMS	equ	205Q
.DAD	equ	206Q		; 3.0

; ---- Error codes (ECDEF) ----
EC.EOF	equ	1		; end of file
EC.EOM	equ	2		; end of media
EC.ILC	equ	3		; illegal SCALL code
EC.CNA	equ	4		; channel not available
EC.DNS	equ	5		; device not suitable
EC.IDN	equ	6		; illegal device name
EC.IFN	equ	7		; illegal file name
EC.NRD	equ	8		; no room for device driver
EC.FNO	equ	9		; channel not open
EC.ILR	equ	10		; illegal request
EC.FUC	equ	11		; file usage conflict
EC.FNF	equ	12		; file name not found
EC.UND	equ	13		; unknown device
EC.ICN	equ	14		; illegal channel number
EC.DIF	equ	15		; directory full
EC.IFC	equ	16		; illegal file contents
EC.NEM	equ	17		; not enough memory
EC.RF	equ	18		; read failure
EC.WF	equ	19		; write failure
EC.WPV	equ	20		; write protection violation
EC.WP	equ	21		; disk write protected
EC.FAP	equ	22		; file already present
EC.DDA	equ	23		; device driver abort
EC.FL	equ	24		; file locked
EC.FAO	equ	25		; file already open
EC.IS	equ	26		; illegal switch
EC.UUN	equ	27		; unknown unit number
EC.FNR	equ	28		; file name required
EC.DIW	equ	29		; device is not writable
EC.UNA	equ	30		; unit not available
EC.ILV	equ	31		; illegal value
EC.ILO	equ	32		; illegal option
EC.VPM	equ	33		; volume presently mounted on device
EC.NVM	equ	34		; no volume presently mounted
EC.FOD	equ	35		; file open on device
EC.NPM	equ	36		; no provisions made for remounting more disks
EC.DNI	equ	37		; disk not initialized
EC.DNR	equ	38		; disk is not readable
EC.DSC	equ	39		; disk structure is corrupt
EC.NCV	equ	40		; not correct version of HDOS
EC.NOS	equ	41		; no operating system mounted
EC.IOI	equ	42		; illegal overlay index
EC.OTL	equ	43		; overlay too large

; ---- .ABS file header (ABSDEF) ----
;   377Q, file type 000Q, load address, length, entry address
ABSID	equ	377Q
ABSTYP	equ	000Q
ABSHLEN	equ	8

; ABSHDR start,len,entry - emit the .ABS header. Put it 8 bytes
; before the load address: org USERFWA-8.
ABSHDR	macro	start,len,entry
	db	ABSID,ABSTYP
	dw	start,len,entry
	endm

; ---- System area, 2000H-227FH (MTRRAM, HOSEQU, ESVAL) ----
; Addresses checked against a dump of HDOS 2.0 in the emulator.

.TICCNT	equ	201Bh		; 2 ms clock tick counter (monitor)
.UIVEC	equ	201Fh		; RAM jump slots for RST 1..7, 3 bytes
				; each: RST n jumps via .UIVEC+3*(n-1)
S.EXITA	equ	2040h		; jump to system exit
S.VAL	equ	20BFh		; system values:
S.DATE	equ	20BFh		;   date, 9 ASCII chars (dd-Mmm-yy)
S.DATC	equ	20C8h		;   coded date
S.TIME	equ	20CAh		;   3.0: BCD time (zero in 2.0)
S.CLKTR	equ	20CDh		;   3.0: clock task flag (zero in 2.0)
S.HIMEM	equ	20CEh		;   hardware memory top (FFFFH on 64K)
S.SYSM	equ	20D0h		;   FWA of resident system
S.USRM	equ	20D2h		;   LWA of user memory
S.CSLMD	equ	20D6h		;   console mode (use .CONSL)
S.CONTY	equ	20D7h		;   console type flags
S.CUSOR	equ	20D8h		;   cursor column
S.CONWI	equ	20D9h		;   console width
S.CONFL	equ	20DAh		;   console flags (^O, ^S)
S.CAADR	equ	20DBh		;   abort address (valid if >= 256)
S.CCTAB	equ	20DDh		;   ^A, ^B, ^C handler addresses
S.INT	equ	20E3h		; system internal work area (ESINT):
S.CACC	equ	2106h		;   A at the SCALL
S.CODE	equ	2107h		;   SCALL function in progress
S.JUMPS	equ	2108h		;   6 JMPs into resident HDOS
S.MOUNT	equ	211Ah		;   <>0 if the system disk is mounted
S.SCR	equ	2151h		;   address of the system scratch area
				;   (HDOS BASIC uses 512 bytes there)
STACK	equ	2280h		; system stack top (grows down)
USERFWA	equ	2280h		; usual program load address

; S.CSLMD bits
CSL.ECH	equ	10000000b	; suppress echo
CSL.RAW	equ	00000100b	; raw mode (3.0)
CSL.WRP	equ	00000010b	; wrap lines at width
CSL.CHR	equ	00000001b	; character mode

; S.CONTY bits
CTP.BKS	equ	10000000b	; terminal processes backspace
CTP.FF	equ	01000000b	; terminal processes form feed
CTP.MLI	equ	00100000b	; map lower case to upper on input
CTP.MLO	equ	00010000b	; map lower case to upper on output
CTP.2SB	equ	00001000b	; two stop bits
CTP.BKM	equ	00000010b	; map backspace input to rubout
CTP.TAB	equ	00000001b	; terminal supports tabs

; S.CONFL bits
CO.FLG	equ	00000001b	; ^O: output suppressed
CS.FLG	equ	10000000b	; ^S: output stopped
