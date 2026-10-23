//! A backend with no display server, for tests: it records what core asks
//! of it, and replays the events a test queues.
pub const Backend = @import("fake/backend.zig").Backend;
pub const id = @import("types").platform.fake;
