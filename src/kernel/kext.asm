; kext.asm - HCOS.SYS, the kernel extension
;
; Phase 4 of HCOS. HCCP loads it at cold boot to KXBASE, below the CCP,
; and points the TPA top (0006H) at its first bytes, a JMP to the BDOS.
; It holds the HDOS file system (the same modules as HDOS.COM) and the
; KFB layer that lets CP/M programs use files on HDOS disks through the
; BDOS. Warm boot doesn't reload it; HCCP calls kxreset instead.

	.8080
	include	cpm.inc
	include	hdos.inc
	include	hchan.inc
	include	hcos.inc

KX	equ	1			; (the kernel extension)

	org	KXBASE

	jmp	BDOSB+6			; BDOS entry (0005H comes here)
	db	'HCKX'			; signature
	jmp	kxhook
	jmp	kxreset
	db	KXVER

	include	kfb.asm
	include	kxlib.asm
	include	bios.asm
	include	hdosfs.asm
	include	hdoswr.asm
	include	hdosdir.asm

; ---- Data ----
HDATE:	dw	((80-70) << 9) + (1 << 5) + 1	; date for new files: 1-Jan-80
psec:	dw	secbuf			; directory block buffer
pgrt:	dw	grtbuf			; GRT of unit 0 (then 1, 2, 3)
chp:	dw	0			; current slot
chnoex:	db	0
dnam:	ds	14			; decoded name
kdrv:	db	0
kfn:	db	0
kdma:	dw	0
kfcb:	dw	0
kslotn:	db	0
khalf:	db	0
kcunit:	db	0FFh			; unit and sector in dbuf
kclsn:	dw	0
kspg:	db	0
kblk:	dw	0			; search position
kidx:	db	0
kres:	db	0
kdp:	dw	20			; made-up DPB: 20 records a track,
	db	3,7,0			; 1K blocks,
	dw	0,0			; DSM and DRM filled in,
	db	0,0			; no directory blocks or checksums,
	dw	0,0			; no system tracks
KAVLEN	equ	64			; up to 512 blocks
kav:	ds	KAVLEN
kslots:	ds	NKSLOT*CHLEN
kxsp:	dw	0			; the BDOS's SP
	ds	128			; the extension's stack
kxstk:

	ds	255 - (($ - 1) and 255)	; (page aligned)
grtbuf:	ds	NUNIT*256
secbuf:	ds	512
dbuf:	ds	256
KXTOP	equ	$
	assert	KXTOP <= KXEND
