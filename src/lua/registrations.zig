const std = @import("std");
const ziglua = @import("ziglua");
const api = @import("api_docs");
const Registration = @import("util.zig").Registration;

const modules = .{
    @import("animation.zig"),
    @import("arrangers.zig"),
    @import("layout.zig"),
    @import("config.zig"),
    @import("repl.zig"),
};

/// Every pub fn l_<name> in the modules above becomes wm.<name>.
pub const handwritten = blk: {
    @setEvalBranchQuota(100000);
    var regs: []const Registration = &.{};
    for (modules) |m| {
        for (@typeInfo(m).@"struct".decls) |d| {
            if (!std.mem.startsWith(u8, d.name, "l_")) continue;
            regs = regs ++ [_]Registration{.{
                .func = ziglua.wrap(@field(m, d.name)),
                .name = d.name[2..],
            }};
        }
    }
    break :blk regs;
};

/// Everything on the wm table: hand-written functions plus generated commands.
pub const all = handwritten ++ @import("bridge.zig").registrations;

comptime {
    @setEvalBranchQuota(100000);
    for (api.entries) |entry| {
        if (std.mem.eql(u8, entry.category, "Guides")) continue;
        const found = for (all) |reg| {
            if (std.mem.eql(u8, entry.name, reg.name)) break true;
        } else false;
        if (!found) @compileError("api_docs has '" ++ entry.name ++ "' but it is not registered");
    }
    for (all, 0..) |reg, i| {
        const documented = for (api.entries) |entry| {
            if (std.mem.eql(u8, entry.name, reg.name)) break true;
        } else false;
        if (!documented) @compileError("'" ++ reg.name ++ "' has no entry in api_docs");
        for (all[i + 1 ..]) |other| {
            if (std.mem.eql(u8, reg.name, other.name)) @compileError("'" ++ reg.name ++ "' is registered twice");
        }
    }
}
