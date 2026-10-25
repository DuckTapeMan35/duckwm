const std = @import("std");

/// A type to write out, with the name the generator gave it.
pub const Named = struct { T: type, name: []const u8 };

/// snake_case -> PascalCase.
pub fn pascal(comptime s: []const u8) []const u8 {
    @setEvalBranchQuota(100000);
    comptime {
        var out: []const u8 = "";
        var upper = true;
        for (s) |ch| {
            if (ch == '_') {
                upper = true;
                continue;
            }
            out = out ++ [_]u8{if (upper) std.ascii.toUpper(ch) else ch};
            upper = false;
        }
        return out;
    }
}

/// PascalCase -> snake_case.
pub fn snake(comptime s: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (s, 0..) |ch, i| {
            if (std.ascii.isUpper(ch)) {
                if (i > 0) out = out ++ "_";
                out = out ++ [_]u8{std.ascii.toLower(ch)};
            } else out = out ++ [_]u8{ch};
        }
        return out;
    }
}

/// PascalCase or snake_case -> SCREAMING_SNAKE.
pub fn screaming(comptime s: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (s, 0..) |ch, i| {
            if (std.ascii.isUpper(ch) and i > 0) out = out ++ "_";
            out = out ++ [_]u8{std.ascii.toUpper(ch)};
        }
        return out;
    }
}

pub fn is_string(comptime T: type) bool {
    return T == []const u8;
}

/// A slice of anything but bytes: repeated, in protobuf; pointer and length, in C.
pub fn is_list(comptime T: type) bool {
    return @typeInfo(T) == .pointer and !is_string(T);
}
