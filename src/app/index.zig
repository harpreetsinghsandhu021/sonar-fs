const stat = @import("../fs/stat.zig");

// App Configurations
pub const Config = struct {
    root: []const u8,
    icons: bool = true,
    size: bool = true,
    perm: bool = true,
    time: bool = true,
    link: bool = true,
    time_type: stat.timeType = .modified,
    user: bool = true,
    group: bool = true,
    use_fullscreen: bool = false,
};
