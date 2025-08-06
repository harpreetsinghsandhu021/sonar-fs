const std = @import("std");
const Stat = @import("../fs/stat.zig").Stat;
const TimeType = @import("../fs/stat.zig").timeType;
const time_utils = @import("../utils/time.zig");
const string_utils = @import("../utils/string.zig");

// ANSI color codes for different file types
const d = "\x1b[35;1md\x1b[m"; // Purple 'd' represents directories
const l = "\x1b[36;1md\x1b[m"; // Cyan 'l' represents symbolic links
const b = "\x1b[33;1md\x1b[m"; // Yellow 'b' represents block devices
const c = "\x1b[33;1md\x1b[m"; // Yellow 'c' represents character devices

// ANSI color codes for file permissions
const x = "\x1b[32;1mx\x1b[m"; // Green 'x' represents execute permissions
const w = "\x1b[33;1mx\x1b[m"; // Yellow 'w' represents write permissions
const r = "\x1b[31;1mx\x1b[m"; // Red 'r' represents read permissions
const dash = "\x1b[2m-\x1b[m"; // Dimmed '-' represents no permissions

// Formats the file size with appropriate units (bytes, KB, MB, etc.)
pub fn size(stat: Stat, buffer: []u8) ![]u8 {
    const suffix = getSizeSuffix(stat.size);

    if (suffix == 'X') {
        return try std.fmt.bufPrint(buffer, "2LRG", .{});
    }

    // Convert size to unsigned integer to display
    const bytes_unsigned: u64 = @intCast(@max(0, stat.size));

    // For Files smaller than 999 bytes, show exact size
    if (stat.size < 999) {
        return try std.fmt.bufPrint(buffer, "{d:4.0}", .{bytes_unsigned});
    }

    // For larger files, calculated truncated size with one decimal place
    const truncated = @round(getTruncated(stat.size) * 10) / 10;

    // Format numbers less than 10 with one decimal place
    if (truncated < 10) {
        return std.fmt.bufPrint(buffer, "{d:3.1}{c}", .{ truncated, suffix });
    }

    // Format numbers 10 and above with no decimal places
    return std.fmt.bufPrint(buffer, "{d:3.0}{c}", .{ truncated, suffix });
}

// Determines the appropriate suffix based on file size
fn getSizeSuffix(bytes: i64) u8 {
    if (bytes < 1_000) return ' '; // Bytes
    if (bytes < 1_000_000) return 'K'; // KiloBytes
    if (bytes < 1_000_000_000) return 'M'; // Megabytes
    if (bytes < 1_000_000_000_000) return 'G'; // Gigabytes
    if (bytes < 1_000_000_000_000_000) return 'T'; // Terabytes
    if (bytes < 1_000_000_000_000_000_000) return 'P'; // Petabytes
    if (bytes < 1_000_000_000_000_000_000_000) return 'E'; // Exabytes
    return 'X'; // Beyond Exabytes
}

// Converts file size to appropriate unit by dividing by powers of 1000
fn getTruncated(bytes: i64) f64 {
    const bytes_float = @max(0, @as(f64, @floatFromInt(bytes)));
    if (bytes_float < 1_000) return bytes_float;
    if (bytes_float < 1_000_000) return bytes_float / 1_000;
    if (bytes_float < 1_000_000_000) return bytes_float / 1_000_000;
    if (bytes_float < 1_000_000_000_000) return bytes_float / 1_000_000_000;
    if (bytes_float < 1_000_000_000_000_000) return bytes_float / 1_000_000_000_000;
    if (bytes_float < 1_000_000_000_000_000_000) return bytes_float / 1_000_000_000_000_000;
    if (bytes_float < 1_000_000_000_000_000_000_000) return bytes_float / 1_000_000_000_000_000_000;
    return bytes_float;
}

// Formats file permissions in the style similar to 'ls' command
pub fn mode(stat: *Stat, buffer: []u8) ![]u8 {
    // User permissions (owner)
    const read_user = if (stat.hasUserReadPermission()) r else dash;
    const write_user = if (stat.hasUserWritePermission()) w else dash;
    const exec_user = if (stat.hasUserExecutePermission()) x else dash;

    // Group permissions
    const read_group = if (stat.hasGroupReadPermission()) r else dash;
    const write_group = if (stat.hasGroupWritePermission()) w else dash;
    const exec_group = if (stat.hasGroupExecutePermission()) x else dash;

    // Other permissions
    const read_other = if (stat.hasOtherReadPermission()) r else dash;
    const write_other = if (stat.hasOtherWritePermission()) w else dash;
    const exec_other = if (stat.hasOtherExecutePermission()) x else dash;

    // Format the permission like "drwxr-xr-x"
    return std.fmt.bufPrint(buffer, "{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}", .{ itemType(stat.*), read_user, write_user, exec_user, read_group, write_group, exec_group, read_other, write_other, exec_other });
}

// Determines and returns the file type indicator
fn itemType(stat: Stat) []const u8 {
    if (stat.isDir()) {
        return d;
    }

    if (stat.isLinkFile()) {
        return l;
    }

    if (stat.isCharSpecialFile()) {
        return c;
    }

    if (stat.isBlockFile()) {
        return b;
    }

    return " "; // Regular file
}

// Formats timestamp information for files
pub fn time(stat: Stat, time_type: TimeType, output_buffer: []u8) []u8 {
    const timestamp_seconds = switch (time_type) {
        .accessed => stat.atime,
        .changed => stat.ctime,
        .modified => stat.mtime,
    };

    // Format strings for date display
    const date_format = "%d %b";
    // If current year, show time, else show year
    const time_or_year_format = if (time_utils.isCurrentYear(timestamp_seconds)) "%H:%M" else "%Y";

    var temp_buffer: [32]u8 = undefined;

    // Format the first part (day and month)
    var formatted_date = time_utils.strftime(date_format, timestamp_seconds, &temp_buffer);
    const date_width = string_utils.leftPadding(formatted_date, 6, ' ', output_buffer).len; // Left pad to 6 characters

    // Add space b/w date and time
    output_buffer[date_width] = ' ';

    // Format the second part (time or year)
    formatted_date = time_utils.strftime(time_or_year_format, timestamp_seconds, &temp_buffer);
    const time_width = string_utils.leftPadding(formatted_date, 5, ' ', output_buffer[(date_width + 1)..]).len;

    // Return the complete formatted string
    return output_buffer[0..(date_width + 1 + time_width)];
}
