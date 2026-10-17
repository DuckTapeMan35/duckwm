//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const WM = @import("wm").WM;
pub const reload_commands_only = @import("wm").reload_commands_only;
pub const check_commands_file = @import("wm").check_commands_file;

pub const Config = struct {
    pub fn load(wm: *WM) !void {
        return @import("config").load(wm);
    }
};
