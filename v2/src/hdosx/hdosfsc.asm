; hdosfsc.asm - HDOSFS.COM: put the HDOS extension at KXBASE
;
; The shell runs A:HDOSFS when the BDOS has found an HDOS disk and the
; extension isn't in memory. This front part copies the extension (the
; image of kext.asm, which follows it in the file) to KXBASE, says so,
; and installs it with KX.RST, which returns to the shell.

	.8080
	include	cpm.inc
	include	layout.inc

	org	TPA

	jmp	start

; The date for new HDOS files: DATE.COM changes it here, in the file, as
; in HDOS.COM. 'HCDT', 'dd-Mmm-yy', the coded date.
	db	'HCDT'
	db	'01-Jan-80'
sdatc:	dw	((80-70) << 9) + (1 << 5) + 1

start:	lhld	img+KX.LEN-KXBASE	; its code's length
	mov	b,h
	mov	c,l
	lxi	h,img
	lxi	d,KXBASE
mv1:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcx	b
	mov	a,b
	ora	c
	jnz	mv1
	lhld	sdatc
	shld	KX.DATE
	lxi	d,msg
	mvi	c,C_WRITESTR
	call	BDOS
	jmp	KX.RST

msg:	db	'HDOS disks: HDOSFS loaded',13,10,'$'
img:					; (kext's image follows)
