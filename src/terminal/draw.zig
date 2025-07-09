const std = @import("std");
const Allocator = std.mem.Allocator;
const styles = @import("./styles.zig");
const terminal = @import("terminal.zig");
const BufferedWriter = @import("writer.zig").BufferedWriter;

const fs = std.fs;

// Config for Vertical line drawing
const VerticalLineConfig = struct { column: usize = 0, row: usize = 0, length: usize = 0, line_char: []const u8 = "\u{2502}", style_sequence: []const u8 = "" };

// Config for Horizontal line drawing
const HorizontalLineConfig = struct { column: usize = 0, row: usize = 0, length: usize = 0, line_char: []const u8 = "\u{2500}", style_sequence: []const u8 = "" };

// Config for string positioning and styling
const StringConfig = struct {
    column: usize = 0,
    row: usize = 0,
    style_sequence: []const u8 = "",
};

// Unicode box drawing characters configuration
const BoxCharacters = struct {
    // Border characters
    top_border: []const u8 = "\u{2500}", // ─
    bottom_border: []const u8 = "\u{2500}", // ─
    left_border: []const u8 = "\u{2502}", // |
    right_border: []const u8 = "\u{2502}", // |

    // Corner characters
    top_left_corner: []const u8 = "\u{250c}", // ┌
    top_right_corner: []const u8 = "\u{2510}", // ┐
    bottom_right_corner: []const u8 = "\u{2518}", // ┘
    bottom_left_corner: []const u8 = "\u{2514}", // └
};

// Style configuration for box components
const BoxStyleConfig = struct {
    // Border styles
    top_border_style: []const u8 = "",
    bottom_border_style: []const u8 = "",
    left_border_style: []const u8 = "",
    right_border_style: []const u8 = "",

    // Corner styles
    top_left_corner_style: []const u8 = "",
    top_right_corner_style: []const u8 = "",
    bottom_left_corner_style: []const u8 = "",
    bottom_right_corner_style: []const u8 = "",
};

// Configuration for box drawing
const Box = struct {
    column: usize = 0,
    row: usize = 0,
    width: usize = 4, // Horizontal border length
    height: usize = 4, // Vertical border length
    characters: BoxCharacters = .{},
    styles: BoxStyleConfig = .{},
    default_style: []const u8 = "", // Base style, overidden by component specific styles
};

pub const Draw = struct {
    allocator: Allocator,
    writer: BufferedWriter,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const writer = try BufferedWriter.init(allocator, 262_144);

        return Self{
            .allocator = allocator,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.writer.deinit();
        self.allocator.destroy(self.writer);
    }

    pub fn drawVerticalLine(self: *Self, config: VerticalLineConfig) !void {
        if (config.length == 0) return;

        // Draw line character at each position vertically
        for (0..config.length) |offset| {
            if (config.style_sequence.len > 0) {
                // Draw with style
                try self.writer.print("\x1b[{d};{d}H{s}{s}\x1b[m", .{
                    config.row + offset,
                    config.column,
                    config.style_sequence,
                    config.line_char,
                });
            } else {
                // Draw without style
                try self.writer.print("\x1b[{d};{d}H{s}", .{
                    config.row + offset,
                    config.column,
                    config.line_char,
                });
            }
        }
    }

    // Draws a Horizontal line with specified configuration
    pub fn drawHorizontalLine(self: *Self, config: HorizontalLineConfig) !void {
        if (config.length == 0) return;

        // Apply style if specified (before drawing line)
        if (config.style_sequence.len > 0) {
            try self.writer.print("{s}", .{config.style_sequence});
        }

        // Draw line character horizontally at fixed row
        for (0..config.length) |offset| {
            try self.writer.print("\x1b[{d};{d}H{s}", .{
                config.row,
                config.column + offset,
                config.line_char,
            });
        }

        // Reset style if it was applied
        if (config.style_sequence.len > 0) {
            try self.writer.writeAny("\x1b[m");
        }
    }

    // Resolves styles for each box component, using component-specific styles if available, otherwise falling back to default style.
    fn getBoxStyle(config: Box) BoxStyleConfig {
        const default_style = config.default_style;
        const component_styles = config.styles;

        return BoxStyleConfig{
            .top_border_style = if (component_styles.top_border_style.len > 0) component_styles.top_border_style else default_style,
            .bottom_border_style = if (component_styles.bottom_border_style.len > 0) component_styles.bottom_border_style else default_style,
            .left_border_style = if (component_styles.left_border_style.len > 0) component_styles.left_border_style else default_style,
            .right_border_style = if (component_styles.right_border_style.len > 0) component_styles.right_border_style else default_style,
            .top_left_corner_style = if (component_styles.top_left_corner_style.len > 0) component_styles.top_left_corner_style else default_style,
            .top_right_corner_style = if (component_styles.top_right_corner_style.len > 0) component_styles.top_right_corner_style else default_style,
            .bottom_left_corner_style = if (component_styles.bottom_left_corner_style.len > 0) component_styles.bottom_left_corner_style else default_style,
            .bottom_right_corner_style = if (component_styles.bottom_right_corner_style.len > 0) component_styles.bottom_right_corner_style else default_style,
        };
    }

    pub fn box(self: *Self, config: Box) !void {
        const c = config.column;
        const r = config.row;
        const w = config.width;
        const h = config.height;
        const bs = getBoxStyle(config);
        const ch = config.characters;

        // Draw Corners

        // Top Left vertex (┌)
        try self.printString(ch.top_left_corner, .{ .row = r, .column = c, .style_sequence = bs.top_left_corner_style });

        // Top Right vertex (┐)
        try self.printString(ch.top_right_corner, .{ .row = r, .column = c + w + 1, .style_sequence = bs.top_right_corner_style });

        // Bottom Left vertex (└)
        try self.printString(ch.bottom_left_corner, .{ .row = r + h + 1, .column = c, .style_sequence = bs.bottom_left_corner_style });

        // Bottom Right vertex (┘)
        try self.printString(ch.bottom_right_corner, .{ .row = r + h + 1, .column = c + w + 1, .style_sequence = bs.bottom_right_corner_style });

        // Draw Borders

        // Top Border (────)
        try self.drawHorizontalLine(.{ .column = c + 1, .row = r, .len = w, .char = ch.top_border, .style_sequence = bs.top_border_style });

        // Bottom Border (────)
        try self.drawHorizontalLine(.{ .column = c + 1, .row = r + h + 1, .len = w, .char = ch.bottom_border, .style_sequence = bs.bottom_border_style });

        // Left Border (|)
        try self.drawVerticalLine(.{ .column = c, .row = r + 1, .len = h, .char = ch.left_border, .style_sequence = bs.left_border_style });

        // Right Border (|)
        try self.drawVerticalLine(.{ .column = c + w + 1, .row = r + 1, .len = h, .char = ch.right_border, .style_sequence = bs.right_border_style });
    }

    // Prints a string at a specified position on the terminal. This method allows for optional styling of the string.
    // @returns error if the write operation fails.
    pub fn printString(self: *Self, str: []const u8, config: StringConfig) !void {
        if (config.style_sequence.len > 0) {
            _ = try self.writer.print("\x1b[{d};{d}H{s}{s}\x1b[m", .{ config.row, config.column, config.style_sequence, str });
        } else {
            _ = try self.writer.print("\x1b[{d};{d}H{s}", .{ config.row, config.column, str });
        }
    }

    // Moves the cursor to a specified position on the terminal.
    // @error if the write operation fails
    pub fn moveCursor(self: *Self, row: usize, col: usize) !void {
        _ = try self.writer.print("\x1b[{d};{d}H", .{ row, col });
    }

    // Saves the current cursor position.
    pub fn saveCursor(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[s");
    }

    // Loads the previously saved cursor position
    pub fn loadCursor(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[u");
    }

    // Hides the cursor
    pub fn hideCursor(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?25l");
    }

    // Shows the cursor
    pub fn showCursor(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?25h");
    }

    // Enables autowrap, which causes the cursor to move to the next line when it reaches the end of the current line.
    pub fn enableAutowrap(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?7h");
    }

    // Disables autowrap, which causes the cursor to stop at the end of the current line.
    pub fn disableAutowrap(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?7l");
    }

    // Enables the alternate buffer, which is a secondary buffer that can be used to store text.
    pub fn enableAlternateBuffer(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?1049h");
    }

    // Disables the alternate buffer, which causes the terminal to use the primary buffer instead.
    pub fn disableAlternateBuffer(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[?1049l");
    }

    // Clears the screen and moves the cursor to the left position.
    pub fn clearScreen(self: *Self) !void {
        _ = try self.writer.writeAny("\x1b[2J\x1b[H");
    }

    // Clears N lines from the terminal screen from the bottom.
    pub fn clearNLines(self: *Self, n: u16) !void {
        // Get the terminal size
        const size = terminal.getTerminalSize();
        // Create a buffer to store the escape sequence
        var buff: [128]u8 = undefined;
        // Create the ANSI escape sequence to clear N lines from the terminal screen from the bottom
        const slice = try std.fmt.bufPrint(&buff, "\x1b[{d}H\x1b[{d}A\x1b[0J", .{ size.rows, n });
        // Write the escape sequence to the terminal
        _ = try self.writer.writeAny(slice);
    }

    // Clears the lines below the specified row.
    pub fn clearLinesBelow(self: *Self, row: u16) !void {
        var buff: [128]u8 = undefined;
        const slice = try std.fmt.bufPrint(&buff, "\x1b[{d};0H\x1b[0J", .{row});
        _ = try self.writer.writeAny(slice);
    }

    // Clears the line underneath the cursor.
    pub fn clearLine(self: *Self) !void {
        _ = self.writer.write("\x1b[K");
    }
};
