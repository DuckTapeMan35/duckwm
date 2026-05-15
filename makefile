PREFIX    ?= /usr
BINDIR    := $(PREFIX)/bin
SYSCONFDIR ?= /etc
DATADIR   := $(PREFIX)/share
APPDIR    := $(DATADIR)/applications
XSESSDIR  := $(DATADIR)/xsessions
DOCDIR    := $(DATADIR)/doc/duckwm
METADIR   := $(DATADIR)/duckwm/meta

ZIG       ?= zig
BUILD_FLAGS ?=

.PHONY: all build install install-config install-session install-docs \
        install-meta setup-user clean uninstall

# ── Build ─────────────────────────────────────────────────────────────────────

all: build

build:
	$(ZIG) build $(BUILD_FLAGS)

release:
	$(ZIG) build $(BUILD_FLAGS) -Doptimize=ReleaseFast

# ── Install (system-wide, requires root) ─────────────────────────────────────

install: build install-bin install-config install-session install-docs install-meta

install-bin:
	install -Dm755 zig-out/bin/duckwm $(DESTDIR)$(BINDIR)/duckwm

install-config:
	install -Dm644 config/default.lua \
		$(DESTDIR)$(SYSCONFDIR)/duckwm/config.lua

install-session:
	install -Dm644 dist/duckwm.desktop \
		$(DESTDIR)$(XSESSDIR)/duckwm.desktop
	install -Dm644 dist/duckwm.desktop \
		$(DESTDIR)$(APPDIR)/duckwm.desktop

install-docs:
	$(ZIG) build meta $(BUILD_FLAGS)
	install -Dm644 API.md   $(DESTDIR)$(DOCDIR)/API.md
	install -Dm644 API.norg $(DESTDIR)$(DOCDIR)/API.norg

install-meta:
	$(ZIG) build meta $(BUILD_FLAGS)
	install -Dm644 meta/wm.lua $(DESTDIR)$(METADIR)/wm.lua

# ── User setup (run as normal user, no root needed) ──────────────────────────

setup-user:
	@# Config
	@mkdir -p $(HOME)/.config/duckwm
	@if [ ! -f $(HOME)/.config/duckwm/config.lua ]; then \
		cp /etc/duckwm/config.lua $(HOME)/.config/duckwm/config.lua; \
		echo "Installed default config to ~/.config/duckwm/config.lua"; \
	else \
		echo "Config already exists at ~/.config/duckwm/config.lua, skipping"; \
	fi
	@# LuaLS meta
	@mkdir -p $(HOME)/.config/duckwm/meta
	cp $(DESTDIR)$(METADIR)/wm.lua $(HOME)/.config/duckwm/meta/wm.lua
	@echo "Installed LuaLS meta to ~/.config/duckwm/meta/wm.lua"
	@# API docs
	@mkdir -p $(HOME)/.local/share/doc/duckwm
	cp $(DESTDIR)$(DOCDIR)/API.md   $(HOME)/.local/share/doc/duckwm/API.md
	cp $(DESTDIR)$(DOCDIR)/API.norg $(HOME)/.local/share/doc/duckwm/API.norg
	@echo "Installed API docs to ~/.local/share/doc/duckwm/"
	@# .luarc.json
	@if [ ! -f $(HOME)/.config/duckwm/.luarc.json ]; then \
		cp dist/luarc.json $(HOME)/.config/duckwm/.luarc.json; \
		echo "Installed .luarc.json to ~/.config/duckwm/.luarc.json"; \
	else \
		echo ".luarc.json already exists, skipping"; \
	fi
	@echo ""
	@echo "Setup complete. Point your editor's LuaLS workspace at ~/.config/duckwm/"

# ── Uninstall ─────────────────────────────────────────────────────────────────

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/duckwm
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

# ── Clean ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf zig-out zig-cache .zig-cache meta etc API.md API.norg
