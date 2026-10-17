; hisys.asm - what HDOS programs reach directly in HDOS.COM: S.GUP, the
; device, unit and overlay tables, and the S.JUMPS stubs.
;
; Programs run with the ROM in at 0000H-1FFFH, where the rest of
; HDOS.COM is, so these are assembled for HI.SYS in the high buffers
; (above 2000H, .phase in hdos.asm) and start-up copies them there.

; S.GUP - HL -> a unit table pointer (DEV.UNT), A = unit: HL -> that
; unit's entry. Uses F, H, L.
gup:	push	psw
	mov	a,m
	inx	h
	mov	h,m
	mov	l,a
	pop	psw
	push	psw
	ani	7
	rlc
	rlc
	rlc
	add	l
	mov	l,a
	jnc	gup1
	inr	h
gup1:	pop	psw
	ret

; A program called a device driver directly: not supported.
ddrv.x:	mvi	a,EC.DDA
	stc
	ret

; S.JUMPS 0-5 (S.SDD, S.FASER, S.DIREA, S.FCI, S.SCI, S.GUP's place is
; filled in by sysinit): map RAM in and report the call (sjump).
sjtab:	mvi	a,0
	jmp	sjhi
sjlen	equ	$-sjtab
	mvi	a,1
	jmp	sjhi
	mvi	a,2
	jmp	sjhi
	mvi	a,3
	jmp	sjhi
	mvi	a,4
	jmp	sjhi
	mvi	a,5
sjhi:	push	psw
	mvi	a,GPP.RAM
	out	GPP
	pop	psw
	jmp	sjump

; Device table (DEVDEF): name, residence, JMP driver, flags, mounted
; unit mask, units, -> unit table, driver length and group. SY: and
; DK: are both the CP/M drives.
DEVELEN	equ	14
DR.IMPR	equ	03h		; in memory, permanent
devtab:	db	'SY',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.DIR,0Fh,NUNIT
	dw	unttab,0
	db	0
	db	'DK',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.DIR,0Fh,NUNIT
	dw	unttab,0
	db	0
	db	'TT',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.CHR,1,1
	dw	chrunt,0
	db	0
	db	'LP',DR.IMPR,0C3h
	dw	ddrv.x
	db	DT.CHR,1,1
	dw	chrunt,0
	db	0
	db	0			; end

; Unit table (DEVDEF UNT.*): flags, SPG, GRT, GRT sector, dir sector
unttab:	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0
	db	0Fh,2
	dw	0,0,0

chrunt:	db	DT.CHR,0
	dw	0,0,0

; Overlay table: both HDOS overlays in memory and resident, as they
; are in effect (PIP reads OVL.FLB).
ovltab:	dw	0,0,0
	db	3,0
	dw	0,0,0
	db	3,0
