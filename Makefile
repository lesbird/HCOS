# HCOS build. `make tools` once, then `make test`.
# The emulator tests need a built H89 checkout (see tests/h89env.sh).

ZMAC   = tools/zmac/src/zmac
ZFLAGS = -8 -I src/inc
B      = build
INC    = $(wildcard src/inc/*.inc)

SMOKE  = $(B)/smoke/cpmhi.com $(B)/smoke/hdoshi.abs
HDOSTESTS = $(patsubst tests/hdos/%.asm,$(B)/hdos/%.abs,$(wildcard tests/hdos/*.asm))
HDOSCOM = $(B)/hdos.com

.PHONY: all tools test disks clean

all: $(HDOSCOM) $(SMOKE) $(HDOSTESTS)

tools: $(ZMAC)

$(ZMAC):
	tools/setup.sh

# zmac picks the output format from the file suffix, and .cim is the
# raw image from the first byte assembled. Copy it to .com / .abs.
define assemble
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) --oo cim,lst -o $@ -o $(@:.cim=.lst) $<
endef

$(B)/smoke/%.cim: tests/smoke/%.asm $(INC) | $(ZMAC)
	$(assemble)

$(B)/hdos/%.cim: tests/hdos/%.asm $(INC) tests/hdos/test.inc | $(ZMAC)
	$(assemble)

$(B)/hdos.cim: src/hdoscom/hdos.asm $(wildcard src/hdoscom/*.asm) $(INC) | $(ZMAC)
	$(assemble)

%.com: %.cim
	cp $< $@

%.abs: %.cim
	cp $< $@

.SECONDARY:

disks: $(B)/disks/hdos.h8d

$(B)/disks/hdos.h8d:
	tests/mkdisks.sh

test: all disks
	tests/run.sh
	tests/difftest.sh

clean:
	rm -rf $(B)
