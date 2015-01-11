#-----------------------------------------------------------------------------#
# vim: ts=8 sw=8 noexpandtab
#-----------------------------------------------------------------------------#
# Copyright (C) 2014 The Mercury Team
# This file may only be copied under the terms of the GNU Library General
# Public Licence - see the file COPYING in the Mercury distribution.
#-----------------------------------------------------------------------------#

MMC=mmc
MTAGS=mtags
GRADE=hlc.gc
MCFLAGS := -O3 --intermodule-optimization --use-grade-subdirs --grade $(GRADE)
ifdef WINDIR
    MLIBS := -lws2_32
endif

MERCURY_FILES=$(wildcard *.m)

all: libnet.so echo test_lookups

libnet.so: $(MERCURY_FILES)
	$(MMC) $(MCFLAGS) --make libnet $(MLIBS)

echo: $(MERCURY_FILES)
	$(MMC) $(MCFLAGS) --make echo $(MLIBS)

test_lookups: $(MERCURY_FILES)
	$(MMC) $(MCFLAGS) --make test_lookups

tags: $(MERCURY_FILES)
	$(MTAGS) $(MERCURY_FILES)

.PHONY: clean
clean:
	rm -rf Mercury *.mh *.err \
		echo test_lookups libnet.so libnet.a \
		net.init \
		tags
