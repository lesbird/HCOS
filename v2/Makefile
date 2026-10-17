# HCOS version 2 build. Uses version 1's pinned zmac (`make tools` at the
# top level, or here). Output goes to v2/build/. See docs/PLAN.md.

TOP    = ..
ZMAC   = $(TOP)/tools/zmac/src/zmac
H89DIR ?= $(TOP)/../H89
ZFLAGS = -8 -I src/inc
B      = build

.PHONY: all tools clean

all:
	@echo "HCOS v2: nothing to build yet (phase 0, see docs/PLAN.md)"

tools: $(ZMAC)

$(ZMAC):
	$(TOP)/tools/setup.sh

clean:
	rm -rf $(B)
