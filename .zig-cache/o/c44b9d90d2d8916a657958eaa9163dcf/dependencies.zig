pub const packages = struct {
    pub const @"N-V-__8AABAhDAAIlXL7OA-0Z5sWQh_FOFGoImvOvJzkRGOg" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAGuAFQAFQL34FRuOIGC9klkZq44uTTan4cUS9vas" = struct {
        pub const available = true;
        pub const build_root = "/home/duck/duckwm/zig-pkg/N-V-__8AAGuAFQAFQL34FRuOIGC9klkZq44uTTan4cUS9vas";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAHD3twASfaoQIBT7MgqysHE9qE1pnme3FsEVRc84" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAKEzFAAA695b9LXBhUSVK5MAV_VKSm1mEj3Acbze" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AALg2DgDVsrOXOPBkTZ7Vt0MZc_Gha5N--G1M-FiH" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AALihEACTeiI1Me9rP-qPZT3BNTELDoSAXn76FIhw" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAODpQgCVrpfzE2ze9FA_rOuByh3WKyIyk5iS_o9a" = struct {
        pub const available = false;
    };
    pub const @"aro-0.0.0-JSD1Qi7QNgDnfcrdEJf82v3o6MhZySjYVrtdfEf3E4Se" = struct {
        pub const build_root = "/home/duck/duckwm/zig-pkg/aro-0.0.0-JSD1Qi7QNgDnfcrdEJf82v3o6MhZySjYVrtdfEf3E4Se";
        pub const build_zig = @import("aro-0.0.0-JSD1Qi7QNgDnfcrdEJf82v3o6MhZySjYVrtdfEf3E4Se");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"translate_c-0.0.0-Q_BUWpf0BgAwrh5AM-acJcslN_YPEhcoCVKbbNjwuUTJ" = struct {
        pub const build_root = "/home/duck/duckwm/zig-pkg/translate_c-0.0.0-Q_BUWpf0BgAwrh5AM-acJcslN_YPEhcoCVKbbNjwuUTJ";
        pub const build_zig = @import("translate_c-0.0.0-Q_BUWpf0BgAwrh5AM-acJcslN_YPEhcoCVKbbNjwuUTJ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "aro", "aro-0.0.0-JSD1Qi7QNgDnfcrdEJf82v3o6MhZySjYVrtdfEf3E4Se" },
        };
    };
    pub const @"zlua-0.1.0-hGRpC298BQBZ-R18LaiSRcZyfX36wUrsb_MXJUOIIxog" = struct {
        pub const build_root = "/home/duck/duckwm/zig-pkg/zlua-0.1.0-hGRpC298BQBZ-R18LaiSRcZyfX36wUrsb_MXJUOIIxog";
        pub const build_zig = @import("zlua-0.1.0-hGRpC298BQBZ-R18LaiSRcZyfX36wUrsb_MXJUOIIxog");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "lua51", "N-V-__8AABAhDAAIlXL7OA-0Z5sWQh_FOFGoImvOvJzkRGOg" },
            .{ "lua52", "N-V-__8AALg2DgDVsrOXOPBkTZ7Vt0MZc_Gha5N--G1M-FiH" },
            .{ "lua53", "N-V-__8AALihEACTeiI1Me9rP-qPZT3BNTELDoSAXn76FIhw" },
            .{ "lua54", "N-V-__8AAKEzFAAA695b9LXBhUSVK5MAV_VKSm1mEj3Acbze" },
            .{ "lua55", "N-V-__8AAGuAFQAFQL34FRuOIGC9klkZq44uTTan4cUS9vas" },
            .{ "luajit", "N-V-__8AAODpQgCVrpfzE2ze9FA_rOuByh3WKyIyk5iS_o9a" },
            .{ "luau", "N-V-__8AAHD3twASfaoQIBT7MgqysHE9qE1pnme3FsEVRc84" },
            .{ "translate_c", "translate_c-0.0.0-Q_BUWpf0BgAwrh5AM-acJcslN_YPEhcoCVKbbNjwuUTJ" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "ziglua", "zlua-0.1.0-hGRpC298BQBZ-R18LaiSRcZyfX36wUrsb_MXJUOIIxog" },
};
