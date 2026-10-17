const std = @import("std");
const types = @import("types");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const wire = @import("protocol").wire;
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

// ---- pointer bindings ----
fn button(b: types.Button) !types.Button {
    return if (b == 0 or b > 255) error.InvalidButton else b;
}

pub fn set_resize_modifier(wm: *WM, args: Args(.set_resize_modifier), _: Allocator) !Value {
    wm.resize_modifier = args.mods;
    wm.sync_pointer_grabs();
    return .nil;
}

pub fn set_float_modifier(wm: *WM, args: Args(.set_float_modifier), _: Allocator) !Value {
    wm.float_move_modifier = args.mods;
    wm.sync_pointer_grabs();
    return .nil;
}

pub fn set_pan_modifier(wm: *WM, args: Args(.set_pan_modifier), _: Allocator) !Value {
    wm.pan_modifier = args.mods;
    wm.sync_pointer_grabs();
    return .nil;
}

pub fn set_pan_button(wm: *WM, args: Args(.set_pan_button), _: Allocator) !Value {
    wm.pan_button = try button(args.button);
    wm.sync_pointer_grabs();
    return .nil;
}

pub fn set_float_move_button(wm: *WM, args: Args(.set_float_move_button), _: Allocator) !Value {
    wm.float_move_button = try button(args.button);
    return .nil;
}

pub fn set_float_resize_button(wm: *WM, args: Args(.set_float_resize_button), _: Allocator) !Value {
    wm.float_resize_button = try button(args.button);
    return .nil;
}

// ---- focus behavior ----
pub fn set_click_to_focus(wm: *WM, args: Args(.set_click_to_focus), _: Allocator) !Value {
    wm.set_click_to_focus(args.enabled);
    return .nil;
}

pub fn set_focus_follows_mouse(wm: *WM, args: Args(.set_focus_follows_mouse), _: Allocator) !Value {
    // While a drag suspends it, the setting takes effect when the drag ends.
    if (wm.ffm_suspended) wm.saved_focus_follows_mouse = args.enabled else wm.focus_follows_mouse = args.enabled;
    return .nil;
}

// ---- cursor ----
pub fn get_cursor_pos(wm: *WM, _: void, arena: Allocator) !Value {
    return util.point(arena, wm.backend.pointer_position());
}

pub fn get_cursor_relative_to_focused(wm: *WM, _: void, arena: Allocator) !Value {
    const f = wm.focused orelse return util.point(arena, .{ .x = 0, .y = 0 });
    const p = wm.backend.pointer_position();
    const c = util.center(f);
    return util.point(arena, .{ .x = p.x - c.x, .y = p.y - c.y });
}

pub fn warp_cursor(wm: *WM, args: Args(.warp_cursor), _: Allocator) !Value {
    wm.backend.warp_pointer(.{ .x = args.x, .y = args.y });
    return .nil;
}

pub fn warp_cursor_to_node(wm: *WM, args: Args(.warp_cursor_to_node), _: Allocator) !Value {
    if (wm.get_node_by_id(args.id)) |n| wm.backend.warp_pointer(util.center(n));
    return .nil;
}

pub fn get_mouse_node(wm: *WM, _: void, _: Allocator) !Value {
    const n = wm.node_at(wm.backend.pointer_position()) orelse return .nil;
    return util.id_value(wm, n);
}

pub fn set_cursor_theme(wm: *WM, args: Args(.set_cursor_theme), _: Allocator) !Value {
    wm.backend.set_cursor_theme(args.theme, args.size);
    return .nil;
}

// ---- keyboard layout ----
pub fn set_keyboard_layout(wm: *WM, args: Args(.set_keyboard_layout), _: Allocator) !Value {
    const ok = wm.set_keyboard_layout(.{
        .layout = args.layout,
        .variant = args.variant orelse "",
        .options = args.options orelse "",
        .model = args.model orelse "",
    });
    if (!ok) return error.InvalidKeymap;
    return .nil;
}

pub fn set_keyboard_layout_index(wm: *WM, args: Args(.set_keyboard_layout_index), _: Allocator) !Value {
    wm.set_keyboard_layout_index(args.index);
    return .nil;
}

pub fn bind_commands(wm: *WM, args: Args(.bind_commands), arena: Allocator) !Value {
    if (args.commands.len == 0) return error.EmptyBind;
    const keysym = wm.backend.keysym_from_name(args.key) orelse return error.UnknownKey;
    const encoded = try wm.allocator.dupe(u8, try wire.encode_request(arena, args.commands));
    wm.bind_commands(.{ .mods = args.mods, .keysym = keysym }, encoded);
    return .nil;
}

pub fn bind(wm: *WM, args: Args(.bind), _: Allocator) !Value {
    const keysym = wm.backend.keysym_from_name(args.key) orelse return error.UnknownKey;
    wm.bind_callback(args.mods, keysym, try util.callback(wm, args.callback));
    return .nil;
}

pub fn unbind(wm: *WM, args: Args(.unbind), _: Allocator) !Value {
    const keysym = wm.backend.keysym_from_name(args.key) orelse return error.UnknownKey;
    wm.unbind(.{ .mods = args.mods, .keysym = keysym });
    return .nil;
}
