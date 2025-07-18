const std = @import("std");
const Allocator = std.mem.Allocator;
// Modes of capture
const CaptureType = enum { search, command };

pub const CharArray = std.ArrayList(u8);

is_capturing: bool,
ctype: CaptureType,
buffer: *CharArray, // A Dynamic array which stores the characters the user types
allocator: Allocator,

const Self = @This();
pub fn init(allocator: Allocator, ctype: CaptureType) !Self {
    const buffer = try allocator.create(CharArray);
    buffer.* = CharArray.init(allocator);

    return Self{
        .allocator = allocator,
        .ctype = ctype,
        .buffer = buffer,
        .is_capturing = false,
    };
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
    self.allocator.destroy(self.buffer);
}

// Flips the recording flag to `true`. After this, keystrokes will be captured.
pub fn start(self: *Self) void {
    self.is_capturing = true;
}

pub fn stop(self: *Self, clear: bool) void {
    if (clear) self.buffer.clearAndFree();
    self.is_capturing = false;
}

// This Function processes keystrokes.
//
// It takes raw keyboard input and decides what to do with it. It is called every time user presses a key.
pub fn capture(self: *Self, str: []const u8) !void {
    // If the input is a single character and its ASCII 127 (Backspace)
    if (str.len == 1 and str[0] == 127) {
        // Remove the last character from the buffer
        const new_len = self.buffer.items.len -| 1;
        self.buffer.shrinkRetainingCapacity(new_len);
        return;
    }

    _ = try self.buffer.append(str);
}

pub fn string(self: *Self) []const u8 {
    return self.buffer.items;
}
