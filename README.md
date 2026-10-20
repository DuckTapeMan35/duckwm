# duckwm

A graph-based tiling window manager for X11 and river (Wayland), configured in Lua.

<!-- showcase: a short overview clip (a few layouts, nested workspaces, zoom) -->

## What is it?

Most window managers keep windows in a tree, a matrix or a stack. duckwm keeps
them in a **constraint graph**: each window is a node, and edges say how nodes
relate (left of, aligned with, a cell of a grid, a share of a split). A solver
turns the constraints into positions.

Graphs can act as any of the usual structures (a tree for dwindle and i3-style
splits, a grid, a stack), and resizing has one clear answer: change the
constraint, solve again, and everything that depends on it follows.

Layouts are plain Lua functions. An arranger gets a snapshot of its workspace
and returns the whole layout as data, and duckwm keeps any state the layout
wants per workspace. The default config ships fair, grid, dwindle, scroller2d
and an i3-style manual layout; writing your own takes a few dozen lines.

## Features

- **Two backends:** X11, and river 0.4's window-management protocol on
  Wayland. One config works on both.
- **Lua configuration:** keys, layouts, rules and behaviour, reloaded live when
  you save. A config that fails to load falls back to the system default.
- **Layouts as data:** arrangers return the layout and their state; duckwm
  applies it atomically and keeps the state per workspace.
- **Transactions:** every event, key and command is one transaction. If a
  callback fails or the result is invalid, nothing changes. Lua can group its
  own changes with `wm.transaction(fn)`.
- **Multiple monitors,** i3/sway style: each monitor has its own workspaces.
  Directional focus crosses monitors, focus follows the mouse onto them, and
  windows can be sent between them.
- **Nested workspaces:** workspaces can hold workspaces, shown as live previews.
- **Virtual canvas, panning and zoom:** layouts can be wider or taller than the
  screen (scroller2d is), pan with the mouse or follow focus, and zoom out to
  see the whole canvas.
- **An in-WM prompt,** StumpWM style, with emacs or vi keys: run commands,
  evaluate Lua, or read a line for any purpose of your own (`wm.read_line`).
- **A REPL:** `quack repl` talks to the running WM's Lua.
- **Floating windows:** move and resize with modifier and mouse, glue floats
  together with constraints.
- **Scratchpad, window swallowing, urgency, per-side border colours and
  split-direction indicators.**
- **Animations** on river.
- **IPC:** the `quack` CLI, a protobuf protocol (`proto/duckwm.proto`) for any
  language, and a Python library, `duckwm_py`, which can bind keys and provide
  arrangers from outside the WM.
- **Editor support:** generated LuaLS stubs for completion and inline docs,
  plus the API reference in Markdown and Neorg.

## Showcase

### Layouts

<!-- showcase: cycling fair, grid, dwindle, scroller2d and manual with Super+Shift+N -->

### Resizing in a graph

<!-- showcase: dragging edges and corners, neighbours following -->

### Nested workspaces

<!-- showcase: creating, entering and leaving nested workspaces, previews updating -->

### Scroller2D, panning and zoom

<!-- showcase: opening windows right and below, panning, zooming out to the whole canvas -->

### Multiple monitors

<!-- showcase: focus crossing monitors, sending windows between them, hotplug -->

### The prompt and the REPL

<!-- showcase: Super+R running a command, Super+Ctrl+P evaluating Lua, quack repl -->

## Why a graph?

- **Matrix:** good for grids, but resizing is ambiguous: which windows shrink
  when you drag a corner?
- **Tree:** good for dwindle and i3-style splits, but grids don't fit it
  naturally.
- **Stack:** good for tabbed and monocle layouts, not much else.

A graph covers all three. The cost is speed: solving is more work than walking
a tree, and the structure is pointer-heavy. With the handful of windows on a
workspace, that isn't noticeable.

## Why Lua?

Graphs are expressive enough that hardcoding a couple of layouts would waste
them, so the config is a real language. Lua because it's small, fast, made to
be embedded, and its tables fit layout trees and config naturally. Fennel
compiles to Lua if you prefer a Lisp. The Lua is built into duckwm (5.5, via
ziglua), so there's nothing to install.

## Why X11 and river?

A Wayland compositor does far more than a window manager: rendering, input,
portals and so on. river 0.4 split window management out of the compositor
into a protocol, so a separate program can manage windows without being a
compositor. That's what duckwm's river backend is. On X11, duckwm is an
ordinary window manager. (I am not opposed to making a custom compositor
backend for duckwm on wayland but, much like duckwm itself, it would be
unorthodox and a project onto itself)

## Installation

### Requirements

- Zig 0.16.0
- For X11: libX11, libXft, libXcursor, libXrandr, fontconfig
- For river: river 0.4 or later, wayland, libxkbcommon, fcft, pixman

Lua comes with duckwm; you don't need a system Lua.

### From source

```sh
git clone https://github.com/DuckTapeMan35/duckwm
cd duckwm
zig build -Doptimize=ReleaseSafe -Dplatform=x11 --prefix /usr     # or -Dplatform=river
sudo zig build -Doptimize=ReleaseSafe -Dplatform=x11 --prefix /usr install install-config
```

This installs `duckwm` and `quack` to `/usr/bin` and the default config to
`/etc/duckwm/config.lua`. The backend is chosen at build time.

### Nix

The flake provides the package and a NixOS module (`nix/module.nix`), which
sets up the session, the keyboard layout, and a `duckwm-repl` command.

### Arch Linux (AUR)

```sh
git clone https://aur.archlinux.org/duckwm-git.git
cd duckwm-git
makepkg -si
```

### Starting it

- **X11:** pick duckwm in your display manager, or put `exec duckwm` in
  `~/.xinitrc`.
- **river:** start river with duckwm as its window manager:
  `river -c duckwm`.

## Configuration

Your config is `~/.config/duckwm/config.lua`. Without one, duckwm uses
`/etc/duckwm/config.lua`; copy that file as a starting point.

The default config needs nothing but duckwm and a shell. Super+F1 shows its
keys:

| Keys                        | Action                                                                                   |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| Super+Return                | terminal (`$TERMINAL`, or the first installed of foot, kitty, alacritty, wezterm, xterm) |
| Super+R                     | run a command                                                                            |
| Super+Ctrl+P                | evaluate Lua                                                                             |
| Super+H/J/K/L or arrows     | focus (crosses monitors)                                                                 |
| Super+Shift+H/J/K/L         | swap                                                                                     |
| Super+Ctrl+H/J/K/L          | resize                                                                                   |
| Super+1–9                   | switch workspace; Shift sends the window and follows, Alt just sends it                  |
| Super+, / Super+.           | focus the monitor left / right; Shift sends the window there                             |
| Super+W / E / Escape        | new nested workspace / enter it / leave it                                               |
| Super+Shift+N               | next layout                                                                              |
| Super+T                     | split direction (scroller2d, manual)                                                     |
| Super+F / F11               | float / fullscreen                                                                       |
| Super+S, Super+Shift+Escape | scratchpad, put it back in the tiling                                                    |
| Super+minus / equal / 0     | zoom out / in / whole canvas                                                             |
| Super+Shift+Q               | close                                                                                    |
| Super+Shift+R               | reload                                                                                   |
| Super+Shift+E               | quit                                                                                     |

The config reloads when you save it. If it fails to load, duckwm shows the
error and runs the system default instead, so you're never left without keys.
Each part of the default config is set up separately: if one part fails, the
rest still loads, and Super+F1 lists what went wrong.

## Documentation

`zig build meta` generates:

- `API.md`: the full Lua API, by category
- `API.norg`: the same, for Neorg
- `meta/wm.lua`: LuaLS stubs

`zig build proto` regenerates `proto/duckwm.proto`, the IPC protocol, from the
command definitions.

## IPC

`quack` sends commands to the running WM. Every `wm.*` function that makes
sense outside Lua is a command:

```sh
quack get_focused
quack switch_to_workspace 2
quack get_outputs
quack print_graph
quack reload_config
quack repl            # a Lua REPL in the running WM
```

The protocol is protobuf over a Unix socket, so any language can talk to
duckwm. `duckwm_py` wraps it for Python, including callbacks: a Python program
can bind keys, add rules and provide arrangers.

duckwm can also run without Lua (`--no-lua`), configured entirely by a commands
file (`--commands <file>`) and socket clients. `--check <file>` validates a
commands file.

## Stability

duckwm runs user code against a pointer-heavy graph, so it's built to contain
mistakes. Changes go through transactions that roll back when a callback fails
or the result doesn't validate, and a broken config falls back to the default.
It's still young: strange states and crashes are possible, especially through
IPC, reloads and unusual configs. Bug reports with the `print_graph` output
and which backend is being used are welcome.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
