#-----------------------------------------------------------------------------#
# vim: ts=8 sw=8 noexpandtab
#-----------------------------------------------------------------------------#

include ../Cairo.options

MMC=mmc

PROGS=\
	fill                \
	mask                \
	paint        	    \
	path_close		    \
	setsourcegradient	\
	setsourcergba		\
	showtext            \
	stroke              \
	textextents         \
	tips_ellipse        \
	tips_letter

.PHONY: all
all: $(PROGS)

%: %.m
	$(MMC) --make $@ --ml mercury_cairo --cflags $(CAIRO_CFLAGS) $(CAIRO_LDFLAGS)

.PHONY: test

test: all
	$(foreach PROG,$(PROGS),./$(PROG);)

.PHONY: realclean
realclean:
	$(foreach PROG,$(PROGS),$(MMC) --make $(PROG).realclean;)
	/bin/rm -f *.png
	/bin/rm -rf Mercury
