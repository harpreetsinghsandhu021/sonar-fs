const std = @import("std");
const testing = std.testing;

// ANSI color codes
// Values correspond to standard ANSI color codes (30-37)
pub const Color = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    default = 39,

    // Advanced color modes
    c256, // 256-color mode using \x1b[38;5;{n}m
    rgb, // True color RGB mode using \x1b[38;2;{r};{g};{b}m format
    none, // No color modification required
};

// ANSI SGR(Select Graphic Rendition) Codes
// 1 = Bold
// 2 = Faint
// 3 = Italic
// 4 = Underline
// 5 = Blink
// 7 = Inverse
// 8 = Hidden
// 9 = Strike-through

// Configuration structure for terminal text styling
// Provides comprehensive control over text appearance
pub const StyleConfig = struct {
    // Foreground color
    fg: Color = .none, // Primary foreground color selection
    fg_n: u8 = 0, // Color number for 256-color mode
    fg_r: u8 = 0, // Red component for RGB color
    fg_g: u8 = 0, // Green component for RGB color
    fg_b: u8 = 0, // Blue component for RGB color

    // Foreground color
    bg: Color = .none, // Primary foreground color selection
    bg_n: u8 = 0, // Color number for 256-color mode
    bg_r: u8 = 0, // Red component for RGB color
    bg_g: u8 = 0, // Green component for RGB color
    bg_b: u8 = 0, // Blue component for RGB color

    // Text attributes
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    inverse: bool = false,
    hidden: bool = false,
    strike: bool = false,

    no_style: bool = false, // Disable all styling when true

};

// Generates ANSI escape sequences for terminal text styling.
// @param buffer: Output buffer to store the generated sequence
// @param config: Style configuration specifying desired text attributes and colors
// @returns Slice of buffer containing the generated ANSI sequence
// @error Returns error if buffer is too small or formatting fails
pub fn style(buffer: []u8, config: StyleConfig) ![]u8 {
    // Init ANSI escape sequence
    var slice = try std.fmt.bufPrint(buffer, "\x1b[", .{});
    var index = slice.len;

    // Apply text attributes if enabled
    if (config.bold) {
        slice = try std.fmt.bufPrint(buffer[index..], "1;", .{});
        index += slice.len;
    }

    if (config.faint) {
        slice = try std.fmt.bufPrint(buffer[index..], "2;", .{});
        index += slice.len;
    }

    if (config.italic) {
        slice = try std.fmt.bufPrint(buffer[index..], "3;", .{});
        index += slice.len;
    }

    if (config.underline) {
        slice = try std.fmt.bufPrint(buffer[index..], "4;", .{});
        index += slice.len;
    }

    if (config.blink) {
        slice = try std.fmt.bufPrint(buffer[index..], "5;", .{});
        index += slice.len;
    }

    if (config.faint) {
        slice = try std.fmt.bufPrint(buffer[index..], "2;", .{});
        index += slice.len;
    }

    if (config.inverse) {
        slice = try std.fmt.bufPrint(buffer[index..], "7;", .{});
        index += slice.len;
    }

    if (config.hidden) {
        slice = try std.fmt.bufPrint(buffer[index..], "8;", .{});
        index += slice.len;
    }

    if (config.strike) {
        slice = try std.fmt.bufPrint(buffer[index..], "9;", .{});
        index += slice.len;
    }

    // Apply foreground color formatting
    if (config.fg == .c256) {
        slice = try std.fmt.bufPrint(buffer[index..], "38;5;{d}", .{config.fg_n});
        index += slice.len;
    } else if (config.fg == .rgb) {
        slice = try std.fmt.bufPrint(buffer[index..], "38;2;{d};{d};{d}", .{ config.fg_r, config.fg_g, config.fg_b });
        index += slice.len;
    } else if (config.fg != .none) {
        const n = @intFromEnum(config.fg);
        slice = try std.fmt.bufPrint(buffer[index..], "{d};", .{n});
        index += slice.len;
    }

    // Apply background color formatting
    if (config.bg == .c256) {
        slice = try std.fmt.bufPrint(buffer[index..], "48;5;{d}", .{config.bg_n});
        index += slice.len;
    } else if (config.bg == .rgb) {
        slice = try std.fmt.bufPrint(buffer[index..], "48;2;{d};{d};{d}", .{ config.bg_r, config.bg_g, config.bg_b });
        index += slice.len;
    } else if (config.bg != .none) {
        const n = @intFromEnum(config.bg);
        slice = try std.fmt.bufPrint(buffer[index..], "{d};", .{n});
        index += slice.len;
    }
}
