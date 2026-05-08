//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const WM = @import("wm").WM;

pub const Config = struct {
    pub fn load(wm: *WM) !void {
        return @import("config").load(wm);
    }
};
