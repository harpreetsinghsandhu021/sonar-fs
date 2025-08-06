const std = @import("std");
const Alloctor = std.mem.Allocator;

const stat = @import("../fs/stat.zig");
const State = @import("../context/state.zig");

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

allocator: Alloctor,
state: *State,

const Self = @This();

pub fn init(allocator: Alloctor, config: *Config) !Self {
    const state = try allocator.create(State);
    state.* = try State.init(allocator, config);

    return Self{
        .allocator = allocator,
        .state = state,
    };
}

pub fn deinit(self: *Self) void {
    self.state.deinit();
    self.allocator.destroy(self.state);
}

pub fn run(self: *Self) !void {
    try self.state.preRun();
    defer self.state.postRun() catch {};

    while (true) {
        try self.state.updateViewport();
        try self.state.fillBuffer();
        try self.state.updateView();
        try self.state.printContents();

        const action = try self.state.getAppAction();

        switch (action) {
            .quit => break,
            .no_action => continue,
            else => try self.state.executeAction(action),
        }

        if (self.state.command_to_execute_on_exit.items.len > 0) {
            break;
        }
    }
}
