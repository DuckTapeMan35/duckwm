pub const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xcursor/Xcursor.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("sys/inotify.h");
    @cInclude("poll.h");
    @cInclude("time.h");
});
