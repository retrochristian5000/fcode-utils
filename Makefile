VERSION = 1.0.3

SUBDIRS = toke detok romheaders

all: $(SUBDIRS)

$(SUBDIRS):
	$(MAKE) -C $@

install:
	$(MAKE) -C toke install
	$(MAKE) -C detok install
	$(MAKE) -C romheaders install

clean:
	for dir in $(SUBDIRS); do $(MAKE) -C $$dir clean; done
	rm -f testsuite/toke testsuite/detok


distclean: clean
	find . -name "*.gcda" -exec rm -f \{\} \;
	find . -name "*.gcno" -exec rm -f \{\} \;

check: all
	sh testsuite/test-toke-output-buffer.sh
	sh testsuite/test-ieee1275-fcode-rom.sh

tests: all
	cp toke/toke testsuite
	cp detok/detok testsuite
	cd testsuite && ./AutoExec

coverage: clean
	$(MAKE) -C toke coverage
	$(MAKE) -C detok coverage
	$(MAKE) -C romheaders coverage
	@testsuite/GenCoverage . fcode-suite-$(VERSION) "FCode suite $(VERSION)"
	@testsuite/GenCoverage toke toke-$(VERSION) "Toke $(VERSION)"

.PHONY: all check clean distclean toke detok romheaders tests
