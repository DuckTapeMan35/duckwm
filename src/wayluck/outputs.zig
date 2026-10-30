const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Output = struct {
    /// duckwm's id for it: stays the same while it's connected.
    id: u32,
    state: *State,
    obj: *wayluck.WmOutputV1,
    name: types.OutputInfo.Name = .{},
    rect: types.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    /// What bars and panels leave of it (null: all of it).
    usable: ?types.Rect = null,
    /// The scene it shows: its windows, placed relative to its corner.
    scene: ?*wayluck.WmSceneV1 = null,
};

/// wayluck announced an output; its name and geometry follow, then done.
pub fn add(s: *State, obj: *wayluck.WmOutputV1) void {
    const o = s.allocator.create(Output) catch return obj.destroy();
    o.* = .{ .id = s.next_output_id, .state = s, .obj = obj };
    if (s.manager) |m| o.scene = m.scene() catch null;
    s.next_output_id += 1;
    obj.setListener(*Output, listener, o);
    s.outputs.append(s.allocator, o) catch {};
}

fn listener(obj: *wayluck.WmOutputV1, event: wayluck.WmOutputV1.Event, o: *Output) void {
    const s = o.state;
    switch (event) {
        .name => |e| o.name = .init(std.mem.span(e.name)),
        .geometry => |e| o.rect = .{
            .x = e.x,
            .y = e.y,
            .width = @intCast(@max(e.width, 0)),
            .height = @intCast(@max(e.height, 0)),
        },
        .usable => |e| o.usable = .{
            .x = e.x,
            .y = e.y,
            .width = @intCast(@max(e.width, 0)),
            .height = @intCast(@max(e.height, 0)),
        },
        // Before ready, core hasn't started: it reads outputs when it does.
        .done => if (s.ready) s.push(.reserved_area_changed),
        // Screen sharing: for the virtual outputs the picker makes.
        .capture_started, .capture_stopped => {},
        .removed => {
            for (s.outputs.items, 0..) |x, i| if (x == o) {
                _ = s.outputs.orderedRemove(i);
                break;
            };
            if (o.scene) |scene| scene.destroy();
            obj.destroy();
            s.allocator.destroy(o);
            s.push(.reserved_area_changed);
        },
    }
}

/// Every output, for core.
pub fn list(s: *State, buf: []types.OutputInfo) []types.OutputInfo {
    const n = @min(buf.len, s.outputs.items.len);
    for (s.outputs.items[0..n], buf[0..n]) |o, *info| {
        info.* = .{
            .id = o.id,
            .rect = o.rect,
            .usable = o.usable orelse o.rect,
            .name = o.name,
        };
    }
    return buf[0..n];
}

/// The output a rectangle is on (the one its centre is in), or the first.
pub fn of(s: *State, r: types.Rect) ?*Output {
    const cx = r.x + @as(i32, @intCast(r.width / 2));
    const cy = r.y + @as(i32, @intCast(r.height / 2));
    for (s.outputs.items) |o| {
        const in_x = cx >= o.rect.x and cx < o.rect.x + @as(i32, @intCast(o.rect.width));
        const in_y = cy >= o.rect.y and cy < o.rect.y + @as(i32, @intCast(o.rect.height));
        if (in_x and in_y) return o;
    }
    return if (s.outputs.items.len > 0) s.outputs.items[0] else null;
}
