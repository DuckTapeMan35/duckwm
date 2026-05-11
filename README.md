# What is duckwm?

Duckwm is an X11 graph based window manager that exposes a lua api for its config.

# Why X11?

While not impossible to make duckwm as a wayland compositor the difficulty of that task is rather high.
On X11 a window manager can focus (almost) entirely on managing windows (by handling X11 events and forwarding data to the display server), whereas a wayland compositor must do many other things on top of that (like actually compositing or implementing portals)
The only way this project would be doable on wayland would be to build on top of river, but I wasn't sure it would even function so I took the path of least resistance.

Also personally I'm very interested in the phoenix project

# Graph based?

Most window managers and compositors use one of 3 data structures to represent layouts (matrix, tree, stack)

This results in the layouts you might be familiar with (master/stack, dwindle, grid, etc), however all of these structures have 2 limitations

1. Expression
  Not all layouts are expressible using these data structures and some can't or are extremely difficult to express, for example a tree is great and the correct structure to represent a dwindle layout or i3wms manual layout, but they will inevitably struggle to represent a grid which is easily done with a matrix

2. Resizing
  For example, when using a matrix to represent a grid there is no way to determine what the size of windows relative to the resized window would be, especially when resizing from a corner

By utilizing directed graphs (constraints) duckwm fixes both of these problems. Graphs can degenerate into equivalents of the above structures and they can rather simply resize windows by mutating the size of a window and rerunning the constraint solver to determine the size of all other windows

# Lua Configurable?

Because graphs are so expressive I didn't want to implement 1 or 2 layouts and call it a day. They are the perfect fit for user defined layouts, so a real language as the config was a necessity.
The decision to make lua the configuring language was because:

- lua is simple

Lua was created to teach programming and its incredibly expressive tables are extremely useful when representing a layout in a config

- lua is fast

For an interpreted language lua is among the fastest

- lua is easily embeddable

In addition to being created for teaching lua was also made to be extremely easy to embedded

- fennel

Fennel is a lisp that transpiles into lua, the config is something that benefits from functional programming since it's very idiomatic, so fennel as a lisp has advantages to simplifying configs

(The irony of hyprland moving to lua as the config is not lost on me)

# Disadvantages

Graphs are definitely slower than other data structures, the solver has to figure out the constraints and that can lead to problems. For example if A is left of B and B is left of A the solver will run in circles forever (which is why I hard capped the amount of iterations to 50). To add to that graphs are very pointer heavy which is likely to run into cache misses. That being said on semi-modern hardware this isn't likely to be noticeable.

Duckwm isn't stable. I mean I picked the most volatile combination, running user code, complex data structures and pointers, so it's not unlikely that a project like this will break from time to time.

# How to install?

Simply run `zig build` on the root of the repository and move the resulting binary into `$PATH`. From there you can use it like any other X11 wm (like adding it to your .xinitrc)
For now there is no install script or default config (tho there is a config example in this repository that showcases some layouts), the config path is `~/.config/duck/config.lua`

# Showcase

Here are some videos of what duckwm is capable of:

TODO: record and add videos
