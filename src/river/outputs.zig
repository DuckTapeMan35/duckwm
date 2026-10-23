const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const river = wayland.client.river;
const State = @import("state.zig").State;
const nonneg = @import("util.zig").nonneg;

pub const Output = struct {
    id: u32,
    state: *State,
    obj: *river.OutputV1,
    layer: ?*river.LayerShellOutputV1 = null,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    /// Area left after layer-shell exclusive zones, in global coordinates.
    usable: ?types.Rect = null,
    default_pending: bool = false,

    /// The whole output, in global coordinates.
    pub fn rect(o: *const Output) types.Rect {
        return .{ .x = o.x, .y = o.y, .width = nonneg(o.width), .height = nonneg(o.height) };
    }

    /// What layer-shell bars leave free (the whole output if they reserve nothing).
    pub fn area(o: *const Output) types.Rect {
        return o.usable orelse o.rect();
    }
};

/// river announced an output.
pub fn add(s: *State, obj: *river.OutputV1) void {
    const o = s.allocator.create(Output) catch return obj.destroy();
    o.* = .{ .state = s, .obj = obj, .id = s.next_output_id };
    s.next_output_id += 1;
    obj.setListener(*Output, output_listener, o);
    if (s.layer_shell) |ls| {
        if (ls.getOutput(obj)) |lo| {
            o.layer = lo;
            lo.setListener(*Output, layer_output_listener, o);
        } else |_| {}
    }
    s.outputs.append(s.allocator, o) catch {};
    if (s.primary == null) set_primary(s, o) else s.push(.reserved_area_changed);
}

fn set_primary(s: *State, o: ?*Output) void {
    s.primary = o;
    if (o) |p| p.default_pending = true;
    s.push(.reserved_area_changed);
    s.mark();
}

fn remove(s: *State, o: *Output) void {
    for (s.outputs.items, 0..) |x, i| {
        if (x == o) {
            _ = s.outputs.orderedRemove(i);
            break;
        }
    }
    if (o.layer) |l| l.destroy();
    o.obj.destroy();
    if (s.primary == o) set_primary(s, if (s.outputs.items.len > 0) s.outputs.items[0] else null);
    s.push(.reserved_area_changed);
    s.allocator.destroy(o);
}

/// The output a point is on (the primary if none).
pub fn at(s: *State, p: types.Point) ?*Output {
    for (s.outputs.items) |o| {
        if (p.x >= o.x and p.x < o.x + o.width and p.y >= o.y and p.y < o.y + o.height) return o;
    }
    return s.primary;
}

/// Every configured output for core, the primary first.
pub fn list(s: *const State, buf: []types.OutputInfo) []types.OutputInfo {
    var count: usize = 0;
    if (s.primary) |p| {
        buf[0] = info(s, p);
        count = 1;
    }
    for (s.outputs.items) |o| {
        if (o == s.primary or count == buf.len) continue;
        if (o.width <= 0 or o.height <= 0) continue; // not configured yet
        buf[count] = info(s, o);
        count += 1;
    }
    return buf[0..count];
}

fn info(s: *const State, o: *const Output) types.OutputInfo {
    var usable = o.area();
    if (o == s.primary) if (s.error_bar) |bar| {
        usable.y += @intCast(bar.height);
        usable.height -|= bar.height;
    };
    return .{ .id = o.id, .rect = o.rect(), .usable = usable };
}

fn output_listener(_: *river.OutputV1, event: river.OutputV1.Event, o: *Output) void {
    const s = o.state;
    switch (event) {
        .position => |e| {
            o.x = e.x;
            o.y = e.y;
            s.push(.reserved_area_changed);
        },
        .dimensions => |e| {
            o.width = e.width;
            o.height = e.height;
            s.push(.reserved_area_changed);
        },
        .removed => remove(s, o),
        else => {},
    }
}

fn layer_output_listener(_: *river.LayerShellOutputV1, event: river.LayerShellOutputV1.Event, o: *Output) void {
    switch (event) {
        .non_exclusive_area => |e| {
            o.usable = .{ .x = e.x, .y = e.y, .width = nonneg(e.width), .height = nonneg(e.height) };
            o.state.push(.reserved_area_changed);
        },
    }
}
