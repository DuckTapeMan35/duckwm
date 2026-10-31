pub const Backend = @import("river/backend.zig").Backend;

pub const id = @import("types").platform.river;

test {
    @import("std").testing.refAllDecls(Backend);
}
