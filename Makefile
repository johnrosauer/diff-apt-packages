PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
BASHCOMPDIR = /etc/bash_completion.d

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
DEB_VERSION = $(shell echo "$(VERSION)" | sed -E 's/^v//; s/^([^0-9])/0.0.0-\1/')

.PHONY: install uninstall deb

install:
	install -d $(DESTDIR)$(BINDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages.sh > $(DESTDIR)$(BINDIR)/diff-apt-packages
	chmod 0755 $(DESTDIR)$(BINDIR)/diff-apt-packages
	install -d $(DESTDIR)$(MANDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages.1 | gzip -9 > $(DESTDIR)$(MANDIR)/diff-apt-packages.1.gz
	chmod 0644 $(DESTDIR)$(MANDIR)/diff-apt-packages.1.gz
	install -d $(DESTDIR)$(BASHCOMPDIR)
	sed "s/@VERSION@/$(VERSION)/g" diff-apt-packages-completion.bash > $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages
	chmod 0644 $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/diff-apt-packages
	rm -f $(DESTDIR)$(MANDIR)/diff-apt-packages.1
	rm -f $(DESTDIR)$(MANDIR)/diff-apt-packages.1.gz
	rm -f $(DESTDIR)$(BASHCOMPDIR)/diff-apt-packages

deb:
	$(eval DEB_DIR := /tmp/diff-apt-packages_$(DEB_VERSION)_all)
	rm -rf $(DEB_DIR)
	# Build installation structure in staging directory (using prefix /usr for deb package)
	$(MAKE) install DESTDIR=$(DEB_DIR) PREFIX=/usr
	# Create control directory
	install -d $(DEB_DIR)/DEBIAN
	# Generate control file dynamically
	( \
		echo "Package: diff-apt-packages"; \
		echo "Version: $(DEB_VERSION)"; \
		echo "Section: utils"; \
		echo "Priority: optional"; \
		echo "Architecture: all"; \
		echo "Maintainer: John Rosauer <john.rosauer@gmail.com>"; \
		echo "Description: Compare currently installed APT packages with default Ubuntu ones"; \
		echo " Compare the set of packages currently installed on an Ubuntu system against the"; \
		echo " set of packages that come pre-installed by default for that release version."; \
	) > $(DEB_DIR)/DEBIAN/control
	# Build the package with root ownership for all files
	dpkg-deb --root-owner-group --build $(DEB_DIR) .
	# Cleanup
	rm -rf $(DEB_DIR)
