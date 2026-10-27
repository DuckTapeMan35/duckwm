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
};

/// wayluck announced an output; its name and geometry follow, then done.
pub fn add(s: *State, obj: *wayluck.WmOutputV1) void {
    const o = s.allocator.create(Output) catch return obj.destroy();
    o.* = .{ .id = s.next_output_id, .state = s, .obj = obj };
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
        // Before ready, core hasn't started: it reads outputs when it does.
        .done => if (s.ready) s.push(.reserved_area_changed),
        .removed => {
            for (s.outputs.items, 0..) |x, i| if (x == o) {
                _ = s.outputs.orderedRemove(i);
                break;
            };
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
        info.* = .{ .id = o.id, .rect = o.rect, .usable = o.rect, .name = o.name };
    }
    return buf[0..n];
}
