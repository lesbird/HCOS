# HCOS version 2 build. Uses version 1's pinned zmac (`make tools` at the
# top level, or here). Output goes to v2/build/. See docs/PLAN.md.
#   make        assemble, and make build/hcos.h8d, a disk that boots HCOS
#               (H17 build), build/test17.h8d, the same with the test
#               shell, and build/hcos37.h8d (H17/H37 build)
#   make test   boot them in the H89 emulator and check them

TOP    = ..
ZMAC   = $(TOP)/tools/zmac/src/zmac
H89DIR ?= $(TOP)/../H89
ZFLAGS = -8 -I src/inc
B      = build
INC    = $(wildcard src/inc/*.inc)
.DEFAULT_GOAL = all

H8DTOOL = $(H89DIR)/build/h8dtool

# The Heath CP/M disk whose reserved tracks HCOS takes over: the H89
# emulator's, without CONFIGUR, MOVCPM17 and ASM (for room), and with
# HDOS's ERRORMSG.SYS (a file for the tests to copy). It is also Heath
# CP/M itself, for the tests to compare HCOS with.
BASE17 = $(B)/cpm.h8d
$(BASE17):
	@mkdir -p $(B)/tmp
	cp $(H89DIR)/disks/CPM_2-2-03.H8D $@
	$(H8DTOOL) rm $@ CONFIGUR.COM MOVCPM17.COM ASM.COM >/dev/null
	$(H8DTOOL) get $(H89DIR)/disks/HDOS_2-0_System.h8d -d $(B)/tmp \
	    ERRORMSG.SYS >/dev/null
	$(H8DTOOL) put $@ $(B)/tmp/ERRORMSG.SYS >/dev/null
	rm -rf $(B)/tmp

# The same for the H37: Heath's H17/H37 CP/M disk (booted from the H37),
# without MOVCPM17, MOVCPM37, CONFIGUR and PIE.
BASE37 = $(B)/cpm37.h37
$(BASE37):
	cp $(H89DIR)/disks/CPM-2-2-03-64K-H17-H37-BOOT_00A3A2A6.H37 $@
	$(H8DTOOL) rm $@ MOVCPM17.COM MOVCPM37.COM CONFIGUR.COM PIE.COM >/dev/null

# HCOS's utilities (src/util/), the same on every build: they find the
# BIOS from 0001H. They replace Heath's FORMAT, SYSGEN and DUP (which call
# into Heath's BIOS) on the HCOS disks. (Heath's BIOS.SYS stays: it is
# read-only, and hidden.
UTILS = $(patsubst src/util/%.asm,$(B)/util/%.com,$(filter-out \
	src/util/format.asm,$(wildcard src/util/*.asm)))
HEATHONLY = FORMAT.COM SYSGEN.COM DUP.COM
$(B)/util/%.cim: src/util/%.asm src/util/util.inc $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I src/util --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
$(B)/util/%.com: $(B)/util/%.cim
	cp $< $@

# CP/M test programs (tests/cpm/*.asm), run by tests/cpmdiff.sh.
PROGS = $(patsubst tests/prog/%.asm,$(B)/prog/%.com,$(wildcard tests/prog/*.asm))
HDOSTESTS = $(patsubst tests/hdos/%.asm,$(B)/hdos/%.abs,$(wildcard tests/hdos/*.asm)) \
	    $(patsubst tests/abs/%.asm,$(B)/abs/%.abs,$(wildcard tests/abs/*.asm))
CPMTESTS = $(patsubst tests/cpm/%.asm,$(B)/cpm/%.com,$(wildcard tests/cpm/*.asm))
$(B)/cpm/%.cim: tests/cpm/%.asm tests/cpm/test.inc $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I tests/cpm --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
$(B)/cpm/%.com: $(B)/cpm/%.cim
	cp $< $@

# The system is built for each target, in build/TARGET/: h17 (the BIOS
# at F000H: a 56K TPA) and h37 (the BIOS at E800H: 54K, with room for
# the H37 driver). Everything follows from BIOSB in build/TARGET/
# target.inc. The tests and test programs don't depend on the target.
TARGETS = h17 h37 h37h
BIOSB.h17 = 0F000h
BIOSB.h37 = 0E800h
BIOSB.h37h = 0E800h
BASE.h17 = F000
BASE.h37 = E800
BASE.h37h = E800
# h37h: the H17/H37 build booted from the H37 (its own driver is the
# H37's, and the H17's is H17.COM in the slot).
CORE37.h17 = 0
CORE37.h37 = 0
CORE37.h37h = 1

.PHONY: all tools test clean

all: $(B)/hcos.h8d $(B)/test17.h8d $(B)/hcos37.h8d $(B)/hcos37.h37 \
	$(CPMTESTS) $(PROGS) \
	$(HDOSTESTS)

tools: $(ZMAC)

$(ZMAC):
	$(TOP)/tools/setup.sh

# target T - the rules for build/T/.
define target
$(B)/$(1)/target.inc:
	@mkdir -p $$(@D)
	printf 'BIOSB\tequ\t$(BIOSB.$(1))\nCORE37\tequ\t$(CORE37.$(1))\n' >$$@

$(B)/$(1)/%.cim: src/%.asm $(INC) $(B)/$(1)/target.inc | $(ZMAC)
	@mkdir -p $$(@D)
	$(ZMAC) $(ZFLAGS) -I $(B)/$(1) -I $$(<D) -I src/hdoscom \
	    --oo cim,lst -o $$@ -o $$(@:.cim=.lst) $$<

$(B)/$(1)/bdos/bdos.cim: $(wildcard src/bdos/*.asm)
$(B)/$(1)/shell/shell.cim: $(wildcard src/shell/*.asm)
$(B)/$(1)/bios/bios.cim: $(wildcard src/bios/*.asm)
$(B)/$(1)/hdosx/kext.cim: $(wildcard src/hdosx/*.asm src/hdoscom/*.asm)
$(B)/$(1)/hdoscom/hdos.cim: $(wildcard src/hdoscom/*.asm)

# HDOS.COM runs HDOS programs natively (with the ROM in); its code is in
# the RAM under the ROM, at 0100H-1FFFH. HDOSFS.COM is a front part that
# copies the HDOS extension (kext, built for KXBASE) up there, then the
# extension's image.
$(B)/$(1)/HDOS.COM: $(B)/$(1)/hdoscom/hdos.cim
	cp $$< $$@
$(B)/$(1)/HDOSFS.COM: $(B)/$(1)/hdosx/hdosfsc.cim $(B)/$(1)/hdosx/kext.cim
	cat $$^ >$$@
$(B)/$(1)/bios/h37com.cim: src/bios/h37.asm src/bios/slotldr.inc
$(B)/$(1)/bios/h17com.cim: src/bios/h17.asm src/bios/slotldr.inc
$(B)/$(1)/H37.COM: $(B)/$(1)/bios/h37com.cim
	cp $$< $$@
$(B)/$(1)/H17.COM: $(B)/$(1)/bios/h17com.cim
	cp $$< $$@
# FORMAT.COM is built for each build: it uses the drivers' code and the
# BIOS's variables (src/util/format.asm).
$(B)/$(1)/util/format.cim: src/util/format.asm src/util/util.inc \
		src/bios/h17.asm src/bios/h37.asm src/bios/biosram.inc
	@mkdir -p $$(@D)
	$(ZMAC) $(ZFLAGS) -I $(B)/$(1) -I src/util -I src/bios \
	    --oo cim,lst -o $$@ -o $$(@:.cim=.lst) $$<
$(B)/$(1)/FORMAT.COM: $(B)/$(1)/util/format.cim
	cp $$< $$@

$(1).PARTS = $(B)/$(1)/boot/h17boot.cim $(B)/$(1)/boot/h37boot.cim \
	$(B)/$(1)/bdos/bdos.cim $(B)/$(1)/bios/bios.cim
endef
$(foreach t,$(TARGETS),$(eval $(call target,$(t))))

# hcosdisk OUT TARGET SHELL [BASE BOOT] - a Heath CP/M disk with HCOS in
# its reserved tracks (an H17 disk unless BASE and BOOT say otherwise),
# HCOS's utilities in place of Heath's, and the build's HDOS.COM and
# HDOSFS.COM.
define hcosdisk
	python3 tools/mksys.py $(or $(4),$(BASE17)) $(1) --base $(BASE.$(2)) \
	    --boot $(B)/$(2)/boot/$(or $(5),h17boot).cim --shell $(3) \
	    --bdos $(B)/$(2)/bdos/bdos.cim --bios $(B)/$(2)/bios/bios.cim
	$(H8DTOOL) rm $(1) $(HEATHONLY) >/dev/null 2>&1 || true
	$(H8DTOOL) put $(1) $(B)/$(2)/HDOSFS.COM $(B)/$(2)/HDOS.COM \
	    $(B)/$(2)/FORMAT.COM $(UTILS) >/dev/null
endef

# build/hcos.h8d: the H17 build, with HDOS.COM and HDOSFS.COM.
# build/test17.h8d: the same with the test shell, for the BIOS tests.
# build/hcos37.h8d: the H17/H37 build, on an H17 disk, booted from it.
$(B)/hcos.h8d: $(h17.PARTS) $(B)/h17/shell/shell.cim tools/mksys.py \
		$(BASE17) $(B)/h17/HDOSFS.COM $(B)/h17/HDOS.COM $(UTILS) \
		$(B)/h17/FORMAT.COM
	$(call hcosdisk,$@,h17,$(B)/h17/shell/shell.cim)
$(B)/test17.h8d: $(h17.PARTS) $(B)/h17/shell/tshell.cim tools/mksys.py \
		$(BASE17) $(B)/h17/HDOSFS.COM $(B)/h17/HDOS.COM $(UTILS) \
		$(B)/h17/FORMAT.COM
	$(call hcosdisk,$@,h17,$(B)/h17/shell/tshell.cim)
$(B)/hcos37.h8d: $(h37.PARTS) $(B)/h37/shell/shell.cim tools/mksys.py \
		$(BASE17) $(B)/h37/HDOSFS.COM $(B)/h37/HDOS.COM $(B)/h37/H37.COM \
		$(UTILS) $(B)/h37/FORMAT.COM
	$(call hcosdisk,$@,h37,$(B)/h37/shell/shell.cim)
	$(H8DTOOL) put $@ $(B)/h37/H37.COM >/dev/null
# build/hcos37.h37: the H17/H37 build on an H37 disk, booted from the H37.
$(B)/hcos37.h37: $(h37h.PARTS) $(B)/h37h/shell/shell.cim tools/mksys.py \
		$(BASE37) $(B)/h37h/HDOSFS.COM $(B)/h37h/HDOS.COM $(B)/h37h/H17.COM \
		$(UTILS) $(B)/h37h/FORMAT.COM
	$(call hcosdisk,$@,h37h,$(B)/h37h/shell/shell.cim,$(BASE37),h37boot)
	$(H8DTOOL) put $@ $(B)/h37h/H17.COM >/dev/null

# Programs the tests run (tests/prog/*.asm).
$(B)/prog/%.cim: tests/prog/%.asm $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
$(B)/prog/%.com: $(B)/prog/%.cim
	cp $< $@
# HDOS test programs: tests/hdos/ (run by tests/difftest.sh on real
# HDOS and on HCOS) and tests/abs/ (by tests/run.sh).
$(B)/hdos/%.cim: tests/hdos/%.asm tests/hdos/test.inc $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I tests/hdos --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
$(B)/abs/%.cim: tests/abs/%.asm $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
%.abs: %.cim
	cp $< $@

# An HDOS 2.0 disk with room on it, for the tests (tests/mkhdos.sh),
# and Heath's HDOS programs from it.
$(B)/hdos.h8d:
	tests/mkhdos.sh
	mkdir -p $(B)/hdosprog
	$(H8DTOOL) get $@ -d $(B)/hdosprog >/dev/null

test: all $(B)/hdos.h8d
	tests/run.sh
	tests/cpmdiff.sh
	tests/difftest.sh

clean:
	rm -rf $(B)
.SECONDARY:
