pub const Backend = @import("wayluck/backend.zig").Backend;
pub const id = @import("types").platform.wayluck;

test {
    @import("std").testing.refAllDecls(Backend);
}
