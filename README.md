# duckwm

A graph-based X11 window manager with a Lua configuration API.

## What is it?

duckwm manages windows by representing layouts as constraint graphs rather than the trees, matrices, or stacks used by most window managers. You configure it entirely in Lua — including defining your own layouts from scratch.

## Why graph-based?

Most window managers use one of three data structures for layouts:

- **Matrix** — good for grids, but resizing is ambiguous (which windows shrink when you resize a corner?)
- **Tree** — good for dwindle/i3-style splits, but struggles to represent grids naturally
- **Stack** — good for tabbed or monocle layouts, not much else

Graphs subsume all of these. They can degenerate into any of the above structures, and resizing is solved cleanly: mutate a window's size, rerun the constraint solver, and all other windows adjust accordingly.

The tradeoff is that graphs are slower — the solver iterates until constraints converge (capped at 50 iterations to prevent infinite loops from contradictory constraints) and they are pointer-heavy, which can cause cache misses. On modern hardware this is not noticeable in practice.

## Why Lua?

Graphs are expressive enough that hardcoding one or two layouts would be a waste. A real scripting language as the config is the right fit, and Lua specifically because:

- **Simple** — Lua was designed for teaching; its table type maps naturally to layout trees and configuration
- **Fast** — among the fastest interpreted languages
- **Embeddable** — Lua was built to be embedded, the integration is trivial
- **Fennel** — Fennel is a Lisp that compiles to Lua; if you prefer a functional style for your config it works out of the box

## Why X11 and not Wayland?

A Wayland compositor has to do significantly more than a window manager: compositing, portal implementation, input handling, and more. A Wayland-native duckwm would either require building on top of something like river (uncertain compatibility) or implementing all of that from scratch. X11 lets the project focus on what it actually is — a window manager.

## Stability

duckwm runs user Lua code against a pointer-heavy graph structure. That combination means crashes are possible, especially with invalid configs. The live reload system catches config errors and falls back to the default config, but this is not a daily driver recommendation yet.

## Installation

### From source

Requirements: `zig >= 0.16.0`, `libx11`

```bash
git clone https://github.com/DuckTapeMan35/duckwm
cd duckwm
sudo make install PREFIX=/usr
make install-user
```

This installs the binary to `/usr/bin/duckwm`, the system default config to `/etc/duckwm/config.lua`, and sets up your user config, LuaLS meta, and API docs under `~/.config/duckwm/`.

### Arch Linux (AUR)

```bash
git clone https://aur.archlinux.org/duckwm-git.git
cd duckwm-git
makepkg -si
```

### Display manager

After installing, duckwm appears as a session option in SDDM, GDM, and other display managers. To start it manually:

```bash
exec duckwm  # in ~/.xinitrc
```

## Configuration

Your config lives at `~/.config/duckwm/config.lua`. The default config is copied there on first install — edit it to define your keybindings, layouts, and behaviour.

The config is reloaded automatically when you save the file. If the new config has a syntax error it is rejected and the current config stays active. If it has a runtime error duckwm falls back to the system default at `/etc/duckwm/config.lua`.

If you use a Lua language server, `make install-user` installs a `.luarc.json` and LuaLS type stubs under `~/.config/duckwm/` so you get completion and inline documentation for the full `wm.*` API in your editor.

The full API reference is at `~/.config/duckwm/docs/API.md`.

## Showcase

TODO: record and add videos

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
