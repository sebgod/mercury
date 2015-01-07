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
all:
	$(foreach PROG,$(PROGS),$(MMC) --make $(PROG) \
		--cflags $(CAIRO_CFLAGS) --ld-flags $(CAIRO_LDFLAGS);)

.PHONY: realclean
realclean:
	$(foreach PROG,$(PROGS),$(MMC) --make $(PROG).realclean;)
	/bin/rm -rf Mercury
