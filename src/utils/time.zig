const std = @import("std");
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;

const libc = @cImport({
    @cInclude("time.h"); // Import C's time.h for time-related functions
});

// Formats a timestamp using the specified format string.
//
// @param format: The format string for time formatting.
// @param sec: Unix timestamp in seconds
// @param buff: Buffer to store the formatted string.
// @returns slice of formatted string.
pub fn strftime(format: []const u8, sec: isize, buff: []u8) []u8 {
    const time_info = libc.localtime(&sec); // Conver timestamp to local time
    const wlen = libc.strftime(buff.ptr, buff.len, @ptrCast(format.ptr), time_info);
    return buff[0..wlen];
}

// Checks if the given timestamp is from the current year.
//
// @param sec: Unix timestamp in seconds
// @returns true if timestamp is from the current year.
pub fn isCurrentYear(sec: isize) bool {
    const now = libc.time(null); // Get current timestamp
    return year(sec) == year(now);
}

// Calculates the year from a Unix Timestamp.
fn year(sec: isize) isize {
    return @divFloor(sec, 3600 * 24 * 365) + 1970; // Convert seconds to years since epoch.
}
