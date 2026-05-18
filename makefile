PREFIX     ?= /usr
BINDIR     := $(PREFIX)/bin
SYSCONFDIR ?= /etc
DATADIR    := $(PREFIX)/share
XSESSDIR   := $(DATADIR)/xsessions
APPDIR     := $(DATADIR)/applications
DOCDIR     := $(DATADIR)/doc/duckwm
METADIR    := $(DATADIR)/duckwm/meta
ZIG        ?= zig
BUILD_FLAGS ?=

.PHONY: all build release install install-user uninstall clean

all: build

build:
	$(ZIG) build $(BUILD_FLAGS)

release:
	$(ZIG) build $(BUILD_FLAGS) -Doptimize=ReleaseFast

install: build
	install -Dm755 zig-out/bin/duckwm $(DESTDIR)$(BINDIR)/duckwm
	install -Dm755 zig-out/bin/quack   $(DESTDIR)$(BINDIR)/quack
	install -Dm644 config/default.lua \
		$(DESTDIR)$(SYSCONFDIR)/duckwm/config.lua
	install -Dm644 dist/duckwm.desktop \
		$(DESTDIR)$(XSESSDIR)/duckwm.desktop
	install -Dm644 dist/duckwm.desktop \
		$(DESTDIR)$(APPDIR)/duckwm.desktop
	$(ZIG) build meta $(BUILD_FLAGS)
	install -Dm644 API.md      $(DESTDIR)$(DOCDIR)/API.md
	install -Dm644 API.norg    $(DESTDIR)$(DOCDIR)/API.norg
	install -Dm644 meta/wm.lua $(DESTDIR)$(METADIR)/wm.lua
	@echo "System install complete. Run 'make install-user' as yourself to set up your config."

install-user:
	@mkdir -p $(HOME)/.config/duckwm/meta \
	          $(HOME)/.config/duckwm/docs
	@if [ ! -f $(HOME)/.config/duckwm/config.lua ]; then \
		cp $(SYSCONFDIR)/duckwm/config.lua \
			$(HOME)/.config/duckwm/config.lua; \
		echo "Installed default config to ~/.config/duckwm/config.lua"; \
	else \
		echo "Config already exists at ~/.config/duckwm/config.lua, skipping"; \
	fi
	cp $(METADIR)/wm.lua  $(HOME)/.config/duckwm/meta/wm.lua
	cp $(DOCDIR)/API.md   $(HOME)/.config/duckwm/docs/API.md
	cp $(DOCDIR)/API.norg $(HOME)/.config/duckwm/docs/API.norg
	@if [ ! -f $(HOME)/.config/duckwm/.luarc.json ]; then \
		cp dist/luarc.json $(HOME)/.config/duckwm/.luarc.json; \
		echo "Installed .luarc.json to ~/.config/duckwm/.luarc.json"; \
	else \
		echo ".luarc.json already exists, skipping"; \
	fi
	@echo "User setup complete. Config at ~/.config/duckwm/"

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/duckwm
	rm -f  $(DESTDIR)$(BINDIR)/quack
	rm -f  $(DESTDIR)$(SYSCONFDIR)/duckwm/config.lua
	rm -f  $(DESTDIR)$(XSESSDIR)/duckwm.desktop
	rm -f  $(DESTDIR)$(APPDIR)/duckwm.desktop
	rm -f  $(DESTDIR)$(DOCDIR)/API.md
	rm -f  $(DESTDIR)$(DOCDIR)/API.norg
	rm -f  $(DESTDIR)$(METADIR)/wm.lua
	rmdir --ignore-fail-on-non-empty \
		$(DESTDIR)$(SYSCONFDIR)/duckwm \
		$(DESTDIR)$(DOCDIR) \
		$(DESTDIR)$(METADIR) 2>/dev/null || true

clean:
	rm -rf zig-out zig-cache .zig-cache meta etc API.md API.norg
