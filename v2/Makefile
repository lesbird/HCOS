# HCOS version 2 build. Uses version 1's pinned zmac (`make tools` at the
# top level, or here). Output goes to v2/build/. See docs/PLAN.md.
#   make        assemble, and make build/hcos.h8d, a disk that boots HCOS
#   make test   boot it in the H89 emulator and check it

TOP    = ..
ZMAC   = $(TOP)/tools/zmac/src/zmac
H89DIR ?= $(TOP)/../H89
ZFLAGS = -8 -I src/inc
B      = build
INC    = $(wildcard src/inc/*.inc)

# The Heath CP/M disk whose reserved tracks HCOS takes over.
BASE17 = $(H89DIR)/disks/CPM_2-2-03.H8D

PARTS  = $(B)/boot/h17boot.cim $(B)/shell/tshell.cim $(B)/bios/bios.cim

.PHONY: all tools test clean

all: $(B)/hcos.h8d

tools: $(ZMAC)

$(ZMAC):
	$(TOP)/tools/setup.sh

$(B)/%.cim: src/%.asm $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) --oo cim,lst -o $@ -o $(@:.cim=.lst) $<

$(B)/hcos.h8d: $(PARTS) tools/mksys.py
	python3 tools/mksys.py $(BASE17) $@ --boot $(B)/boot/h17boot.cim \
	    --shell $(B)/shell/tshell.cim --bios $(B)/bios/bios.cim

test: $(B)/hcos.h8d
	tests/run.sh

clean:
	rm -rf $(B)
