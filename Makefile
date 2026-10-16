# HCOS build. `make tools` once, then `make test`. `make hcos` makes
# build/disks/hcos.h8d, a Heath CP/M disk that boots HCOS.
# The emulator tests need a built H89 checkout (see tests/h89env.sh).

ZMAC   = tools/zmac/src/zmac
ZFLAGS = -8 -I src/inc
B      = build
INC    = $(wildcard src/inc/*.inc)

SMOKE  = $(B)/smoke/cpmhi.com $(B)/smoke/hdoshi.abs
HDOSTESTS = $(patsubst tests/hdos/%.asm,$(B)/hdos/%.abs,$(wildcard tests/hdos/*.asm))
CPMTESTS = $(patsubst tests/cpm/%.asm,$(B)/cpm/%.com,$(wildcard tests/cpm/*.asm))
HDOSCOM = $(B)/hdos.com

.PHONY: all tools test test-cpm test-hcos hcos disks clean

all: $(HDOSCOM) $(SMOKE) $(HDOSTESTS) $(CPMTESTS) $(B)/kernel/bdos.cim

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

$(B)/cpm/%.cim: tests/cpm/%.asm $(INC) tests/cpm/test.inc | $(ZMAC)
	$(assemble)

$(B)/hdos/%.cim: tests/hdos/%.asm $(INC) tests/hdos/test.inc | $(ZMAC)
	$(assemble)

# The HCOS kernel (phase 3: the BDOS) and a boot disk with it.
$(B)/kernel/bdos.cim: src/kernel/bdos.asm $(wildcard src/kernel/*.asm) $(INC) | $(ZMAC)
	@mkdir -p $(@D)
	$(ZMAC) $(ZFLAGS) -I src/kernel --oo cim,lst -o $@ -o $(@:.cim=.lst) $<

$(B)/disks/hcos.h8d: $(B)/disks/hdos.h8d $(B)/kernel/bdos.cim tools/sysgen.py
	python3 tools/sysgen.py $(B)/disks/cpm.h8d $(B)/kernel/bdos.cim $@

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

# Everything: the tests on Heath CP/M, the BDOS compared with CP/M's,
# then the tests again booting HCOS.
test: test-cpm test-hcos

test-cpm: all disks
	tests/run.sh
	tests/difftest.sh

test-hcos: all disks $(B)/disks/hcos.h8d
	tests/cpmdiff.sh
	CPMDISK=hcos tests/run.sh
	CPMDISK=hcos tests/difftest.sh

hcos: $(B)/disks/hcos.h8d

clean:
	rm -rf $(B)
