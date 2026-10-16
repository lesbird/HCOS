; hchan.inc - HDOS channel table layout, shared by HDOS.COM and the
; HCOS kernel extension

; Channel table entry
CH.MODE	equ	0		; CM.* below
CH.FCB	equ	1		; CP/M FCB
CH.DNAM	equ	CH.FCB+FCBLEN	; decoded name (dnam layout)
CHLEN	equ	CH.DNAM+14
NCHAN	equ	7		; channels -1 .. 5

CM.CLS	equ	0		; closed
CM.RD	equ	1		; disk file, read
CM.WR	equ	2		; disk file, write (as NAME.$$$)
CM.UPD	equ	3		; disk file, update
CM.TT	equ	4		; console
CM.LP	equ	5		; printer
CM.HRD	equ	6		; HDOS disk file, read (hdosfs.asm)
CM.SYN	equ	7		; made-up DIRECT.SYS of a CP/M disk
CM.HWR	equ	8		; HDOS disk file, write (hdoswr.asm)
CM.HUP	equ	9		; HDOS disk file, update

DK.DISK	equ	0		; device kinds from dkind
DK.TT	equ	1
DK.LP	equ	2
DK.HDOS	equ	3		; HDOS-format disk
