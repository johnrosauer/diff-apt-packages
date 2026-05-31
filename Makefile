PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
BASHCOMPDIR = /etc/bash_completion.d

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

.PHONY: install uninstall

install:
	install -d $(DESTDIR)$(BINDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages.sh > $(DESTDIR)$(BINDIR)/diff-apt-packages
	chmod 0755 $(DESTDIR)$(BINDIR)/diff-apt-packages
	install -d $(DESTDIR)$(MANDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages.1 > $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	chmod 0644 $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	install -d $(DESTDIR)$(BASHCOMPDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages-completion.bash > $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages
	chmod 0644 $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/diff-apt-packages
	rm -f $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	rm -f $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages
