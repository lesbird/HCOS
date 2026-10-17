; kfsvar.asm - variables of the file system (see kfs.asm)

dlog:	ds	2			; logged-in drives
rodsk:	ds	2			; R/O drives
curdsk:	ds	1			; current drive
curusr:	ds	1			; current user
seldsk:	ds	1			; drive selected for this call
logged:	ds	1			; 0 while logging it in
dma:	ds	2
xltp:	ds	2			; from the DPH:
dirbuf:	ds	2			;   these four in DPH order
dpbp:	ds	2
csvp:	ds	2
alvp:	ds	2
dpb:					; copy of the DPB
spt:	ds	2
bsh:	ds	1
blm:	ds	1
exm:	ds	1
dsm:	ds	2
drm:	ds	2
al0:	ds	1
al1:	ds	1
cks:	ds	2
off:	ds	2
dcnt:	ds	2			; directory entry number
searchl: ds	1			; bytes to match
searcha: ds	2			; pattern FCB
srinfo:	ds	2			; FCB of the last search
mamode:	ds	1
gfcnt:	ds	2
wtype:	ds	1
ckmode:	ds	1
entp:	ds	2			; directory entry being worked on
reqex:	ds	1
seqio:	ds	1			; 1: sequential (advance)
zfill:	ds	1			; 1: zero new blocks (f40)
wrflag:	ds	1			; 1: writing
vrec:	ds	2			; record in the directory entry
blk:	ds	2			; its block
absr:	ds	2			; its logical record on the disk
zcnt:	ds	1
rcr:	ds	1			; random record split up
rex:	ds	1
rs2:	ds	1
fsize:	ds	3
fshi:	ds	1
