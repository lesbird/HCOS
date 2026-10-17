# HCOS version 2 build. Uses version 1's pinned zmac (`make tools` at the
# top level, or here). Output goes to v2/build/. See docs/PLAN.md.
#   make        assemble, and make build/hcos.h8d, a disk that boots HCOS,
#               and build/test17.h8d, the same with the test shell
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

# CP/M test programs (tests/cpm/*.asm), run by tests/cpmdiff.sh.
CPMTESTS = $(patsubst tests/cpm/%.asm,$(B)/cpm/%.com,$(wildcard tests/cpm/*.asm))
$(B)/cpm/%.cim: tests/cpm/%.asm tests/cpm/test.inc $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I tests/cpm --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
$(B)/cpm/%.com: $(B)/cpm/%.cim
	cp $< $@

PARTS  = $(B)/boot/h17boot.cim $(B)/bdos/bdos.cim $(B)/bios/bios.cim

.PHONY: all tools test clean

all: $(B)/hcos.h8d $(B)/test17.h8d $(CPMTESTS)

tools: $(ZMAC)

$(ZMAC):
	$(TOP)/tools/setup.sh

$(B)/%.cim: src/%.asm $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I $(<D) --oo cim,lst -o $@ -o $(@:.cim=.lst) $<

$(B)/bdos/bdos.cim: $(wildcard src/bdos/*.asm)
$(B)/shell/shell.cim: src/shell/shell.asm

# mksys1 OUT SHELL
define mksys1
	python3 tools/mksys.py $(BASE17) $(1) --boot $(B)/boot/h17boot.cim \
	    --shell $(2) --bdos $(B)/bdos/bdos.cim --bios $(B)/bios/bios.cim
endef

$(B)/hcos.h8d: $(PARTS) $(B)/shell/shell.cim tools/mksys.py $(BASE17)
	$(call mksys1,$@,$(B)/shell/shell.cim)
$(B)/test17.h8d: $(PARTS) $(B)/shell/tshell.cim tools/mksys.py $(BASE17)
	$(call mksys1,$@,$(B)/shell/tshell.cim)

test: all
	tests/run.sh
	tests/cpmdiff.sh

clean:
	rm -rf $(B)
