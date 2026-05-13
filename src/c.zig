pub const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
});
