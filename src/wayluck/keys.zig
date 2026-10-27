const types = @import("types");
const xkb = @import("xkbcommon");

/// The keysym called name ("Return", "h"), or null if there's none.
pub fn keysym_from_name(name: []const u8) ?types.Keysym {
    var buf: [64]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const sym = xkb.Keysym.fromName(buf[0..name.len :0], .no_flags);
    if (sym == .NoSymbol) return null;
    return @intCast(@backingInt(sym));
}

/// The keysym's name written into buf, or null if it has none.
pub fn keysym_name(ks: types.Keysym, buf: []u8) ?[]const u8 {
    const sym: xkb.Keysym = @fromBackingInt(@intCast(ks));
    const n = sym.getName(buf.ptr, buf.len);
    if (n <= 0 or n >= buf.len) return null;
    return buf[0..@intCast(n)];
}
