const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Layer = struct {
    state: *State,
    obj: *wayluck.WmLayerV1,
    handle: types.LayerHandle,
    namespace: ?[:0]u8 = null,
    /// Core's heard of it (at its first done).
    announced: bool = false,
    look: Look = .{},
    /// What wayluck has of its look: at first, its own (as Look's
    /// defaults); null after a transaction failed, so it's all said again.
    sent: ?Look = .{},
};

/// How core has a layer surface look: until it says, as wayluck has it.
const Look = struct {
    corners: u32 = 0,
    shadow: ?types.Shadow = null,
    blur: types.Blur = .client,
};

/// wayluck told of a layer surface.
pub fn add(s: *State, obj: *wayluck.WmLayerV1) void {
    const layer = s.allocator.create(Layer) catch return obj.destroy();
    s.next_layer += 1;
    layer.* = .{ .state = s, .obj = obj, .handle = s.next_layer };
    s.layers.put(s.allocator, layer.handle, layer) catch {
        s.allocator.destroy(layer);
        return obj.destroy();
    };
    obj.setListener(*Layer, listener, layer);
}

pub fn namespace(s: *const State, h: types.LayerHandle) ?[]const u8 {
    const layer = s.layers.get(h) orelse return null;
    return layer.namespace;
}

/// Core set some of how layer surface h looks.
pub fn set_look(s: *State, h: types.LayerHandle, change: types.LayerChange) void {
    const layer = s.layers.get(h) orelse return;
    switch (change) {
        .corners => |r| layer.look.corners = r,
        .shadow => |shadow| layer.look.shadow = shadow,
        .blur => |b| layer.look.blur = b,
    }
    s.dirty = true;
}

/// In the turn's transaction: what changed of each layer surface's look.
pub fn tell(s: *State, tx: *wayluck.WmTransactionV1) void {
    var it = s.layers.valueIterator();
    while (it.next()) |lp| {
        const layer = lp.*;
        const look = layer.look;
        const sent = layer.sent;
        if (sent == null or sent.?.corners != look.corners) tx.layerCorners(layer.obj, look.corners);
        if (look.shadow) |sh| if (sent == null or sent.?.shadow == null or !std.meta.eql(sent.?.shadow.?, sh)) {
            tx.layerShadow(layer.obj, sh.blur, sh.spread, sh.x, sh.y, sh.color);
        };
        if (sent == null or sent.?.blur != look.blur) tx.layerBlur(layer.obj, switch (look.blur) {
            .client => .client,
            .on => .on,
            .off => .off,
        });
        layer.sent = look;
    }
}

/// A transaction failed: the next says everything again.
pub fn forget_sent(s: *State) void {
    var it = s.layers.valueIterator();
    while (it.next()) |lp| lp.*.sent = null;
}

pub fn destroy_all(s: *State) void {
    var it = s.layers.valueIterator();
    while (it.next()) |lp| free(s, lp.*);
    s.layers.deinit(s.allocator);
}

fn free(s: *State, layer: *Layer) void {
    layer.obj.destroy();
    if (layer.namespace) |n| s.allocator.free(n);
    s.allocator.destroy(layer);
}

fn listener(_: *wayluck.WmLayerV1, event: wayluck.WmLayerV1.Event, layer: *Layer) void {
    const s = layer.state;
    switch (event) {
        .namespace => |e| {
            if (layer.namespace) |n| s.allocator.free(n);
            layer.namespace = s.allocator.dupeSentinel(u8, std.mem.span(e.namespace), 0) catch null;
        },
        .done => if (!layer.announced) {
            layer.announced = true;
            s.push(.{ .layer_added = layer.handle });
        },
        .closed => {
            _ = s.layers.remove(layer.handle);
            free(s, layer);
        },
        // Its layer and output: rules don't ask (yet).
        .layer, .output => {},
    }
}
