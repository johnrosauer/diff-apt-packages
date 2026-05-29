PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
BASHCOMPDIR = /etc/bash_completion.d

.PHONY: install uninstall

install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 diff-apt-packages.sh $(DESTDIR)$(BINDIR)/diff-apt-packages
	install -d $(DESTDIR)$(MANDIR)
	install -m 0644 diff-apt-packages.1 $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	install -d $(DESTDIR)$(BASHCOMPDIR)
	install -m 0644 diff-apt-packages-completion.bash $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/diff-apt-packages
	rm -f $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	rm -f $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages
