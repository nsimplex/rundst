SRC:=rundst.sh
IDIR:=$(HOME)/bin

# Renamed SRCs
RSRC=$(patsubst %.sh,%,$(SRC))

.PHONY: install uninstall

install: $(SRC)
	for f in $(RSRC); do install -T "$${f}.sh" "$(IDIR)/$$f"; done

uninstall:
	for f in $(RSRC); do rm -f "$(IDIR)/$$f"; done
