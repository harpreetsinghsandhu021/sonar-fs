// Output - Terminal Display Manager
//
// This module is the main interface between the application's internal data structures and the terminal display.
// It's responsible for:
// - Managing Terminal output size
// - Coordinate with Tree module to format and display file listings
// - Handling Command input display
// - Handling Terminal Cleanup on exit

const std = @import("std");
const Draw = @import("../../terminal/draw.zig").Draw;
const BufferedWriter = @import("../../terminal/writer.zig").BufferedWriter;
const Config = @import("../index.zig").Config;
const Tree = @import("../../tree/tree.zig").Tree;
const ViewManager = @import("../../view/viewManager.zig").ViewManager;
const Viewport = @import("../../view/viewport.zig").Viewport;
const Capture = @import("./capture.zig");

allocator: std.mem.Allocator,
display: *Draw,
writer: *BufferedWriter,
treeview: *Tree,
content_buffer: [2048]u8,
style_buffer: [2048]u8,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, config: *Config) !Self {
    const tree = try allocator.create(Tree);
    const writer = try allocator.create(BufferedWriter);
    const display = try allocator.create(Draw);

    writer.* = try BufferedWriter.init(allocator, 2048);
    writer.sync_protocol = .csi;

    display.* = try Draw.init(allocator);
    tree.* = try Tree.init(allocator, config.*);

    try display.hideCursor();
    try display.disableAutowrap();

    return Self{
        .allocator = allocator,
        .display = display,
        .writer = writer,
        .treeview = tree,
        .content_buffer = undefined,
        .style_buffer = undefined,
    };
}

pub fn deinit(self: *Self) void {
    self.display.showCursor() catch {};
    self.display.enableAutowrap() catch {};

    self.writer.deinit();
    self.display.deinit();
    self.treeview.deinit();

    self.allocator.destroy(self.writer);
    self.allocator.destroy(self.display);
    self.allocator.destroy(self.treeview);
}

// THE MAIN DISPLAY FUNCTION
//
// @param start_row: Which row in the terminal to begin drawing
// @param view: View Manager
// @param is_capturing_command: Whether we're currently in command mode
pub fn printContents(self: *Self, start_row: u16, view: *ViewManager, is_capturing_command: bool) !void {
    // Writing to the terminal character-by-character is slow. Buffering collects everything and writes it in one fast operation, preventing flickering.
    try self.writer.enableBuffering();
    defer {
        self.writer.flush() catch {};
        self.writer.disableBuffering();
    }

    try self.display.moveCursor(start_row, 0);
    try self.treeview.printLines(view, self.display, start_row, is_capturing_command);

    // Calculate how many rows were actually drawn, and clear any leftover content below file listing.
    const rendered_rows: u16 = @intCast(view.viewport_end - view.viewport_start);
    try self.display.clearLinesBelow(start_row + rendered_rows + 1);
}

// Displays real-time user input at the bottom of the screen when the user is typing a search query or command.
// Think of it as "display prompt".
pub fn printCaptureString(self: *Self, view: *ViewManager, viewport: *Viewport, capture: *Capture) !void {
    self.writer.enableBuffering();
    defer {
        self.writer.flush();
        self.writer.disableBuffering();
    }

    // Get the current input string from capture object
    const captured = capture.string();
    // Calculate the row where the captured string should be printed:
    // Place it just below the last visible row of the view.
    const row = viewport.viewport_start + view.viewport_end - view.viewport_start;
    // Calculate the starting column so the capture string is right-aligned, leaving one space from the right edge
    // of the viewport.
    const col = viewport.terminal_size.columns - captured.len - 1;

    try self.display.moveCursor(row, col);

    // Choose the sigil ("/" for search, ":" for command) based on capture type
    const sigil = if (capture.ctype == .search) "/" else ":";

    try self.display.printString(sigil, .{ .fg = .black, .bg = .cyan });
    try self.display.printString(captured, .{ .fg = .black, .bg = .yellow });
}
