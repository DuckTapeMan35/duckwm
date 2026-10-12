const std = @import("std");
const c = @import("xlib");
const types = @import("types");

pub const FocusModel = struct {
    /// WM_HINTS.input: may the WM call XSetInputFocus on it?
    accepts_input: bool = true,
    /// Supports WM_TAKE_FOCUS: wants to be told when it gets focus.
    takes_focus: bool = false,
};

/// Bidirectional client <-> frame map.
pub const Frames = struct {
    by_client: std.AutoHashMapUnmanaged(c.Window, c.Window) = .empty,
    by_frame: std.AutoHashMapUnmanaged(c.Window, c.Window) = .empty,
    argb: std.AutoHashMapUnmanaged(c.Window, void) = .empty, // keyed by frame
    focus_models: std.AutoHashMapUnmanaged(c.Window, FocusModel) = .empty,

    pub fn deinit(self: *Frames, gpa: std.mem.Allocator) void {
        self.by_client.deinit(gpa);
        self.by_frame.deinit(gpa);
        self.argb.deinit(gpa);
        self.focus_models.deinit(gpa);
    }

    /// Reserve room for one entry so the later insert cannot fail.
    pub fn reserve(self: *Frames, gpa: std.mem.Allocator) !void {
        try self.by_client.ensureUnusedCapacity(gpa, 1);
        try self.by_frame.ensureUnusedCapacity(gpa, 1);
        try self.argb.ensureUnusedCapacity(gpa, 1);
        try self.focus_models.ensureUnusedCapacity(gpa, 1);
    }

    pub fn put_reserved(self: *Frames, client: c.Window, frame: c.Window, argb: bool, model: FocusModel) void {
        self.by_client.putAssumeCapacity(client, frame);
        self.by_frame.putAssumeCapacity(frame, client);
        if (argb) self.argb.putAssumeCapacity(frame, {});
        self.focus_models.putAssumeCapacity(client, model);
    }

    /// Returns the frame that was attached to client, if any.
    pub fn remove(self: *Frames, client: c.Window) ?c.Window {
        const kv = self.by_client.fetchRemove(client) orelse return null;
        _ = self.by_frame.remove(kv.value);
        _ = self.argb.remove(kv.value);
        _ = self.focus_models.remove(client);
        return kv.value;
    }

    pub fn focus_model(self: *const Frames, client: c.Window) FocusModel {
        return self.focus_models.get(client) orelse .{};
    }

    pub fn is_argb(self: *const Frames, frame: c.Window) bool {
        return self.argb.contains(frame);
    }

    pub fn frame_of(self: *const Frames, client: c.Window) ?c.Window {
        return self.by_client.get(client);
    }

    pub fn client_of(self: *const Frames, frame: c.Window) ?c.Window {
        return self.by_frame.get(frame);
    }
};
