#-----------------------------------------------------------------------------#
# vim: ts=8 sw=8 noexpandtab
#-----------------------------------------------------------------------------#

include ../Cairo.options

MMC=mmc

PROGS=\
	arc                     \
	arc_negative            \
	clip                    \
	clip_image              \
	curve_to                \
	dash                    \
	fill_and_stroke2        \
	fill_style              \
	gradient                \
	hello                   \
	image                   \
	imagepattern            \
	multi_segment_caps      \
	set_line_cap            \
	set_line_join           \
	text                    \
	text_align_center       \
	text_extents

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
