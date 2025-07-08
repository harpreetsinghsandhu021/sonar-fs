const std = @import("std");
const terminal = @import("../terminal/terminal.zig");

const posix = std.posix;

// Implements a viewport system for TUI. Its main purposes are:
// Manage a viewport within terminal window
// Handles terminal dimensions
// Manages cursor positioning
// Implement raw mode terminal handling
pub const Viewport = struct {
    terminal_size: terminal.TerminalSize, // Terminal dimensions (column * rows)
    visible_rows: u16 = 1, // Number of rows available for content display
    viewport_start: u16 = 1, // Starting row position in terminal (1-based index)
    terminal_backup: posix.termios, // Backup of terminal settings for restoration

    const Self = @This();

    // Init viewport with default values and enable raw terminal mode
    pub fn init() !Self {
        var terminal_backup: posix.termios = undefined;
        try terminal.enableRawMode(&terminal_backup);

        return Self{
            .visible_rows = 1,
            .viewport_start = 1,
            .terminal_size = terminal.TerminalSize{ .columns = 1, .rows = 1 },
            .terminal_backup = terminal_backup,
        };
    }

    pub fn deinit(self: *Self) void {
        terminal.disableRawMode(&self.terminal_backup) catch {};
    }

    // This function inits the viewport boundaries by:
    // - Getting terminal dimensions
    // - Calculating where the viewport should start
    // - Updating how many rows can be displayed
    pub fn initBounds(self: *Self) !void {
        self.terminal_size = terminal.getTerminalSize();
        const cursor_position = try terminal.getCursorPosition();
        self.viewport_start = try Self.adjustAndGetInitialStartRow(self.terminal_size, cursor_position);

        self.updateVisibleRows();
    }

    // This function ensures there's enough space to display content:
    // - Determining minimum height needed
    // - Checking available space
    // - Scrolling if necessary to create more space
    pub fn adjustAndGetInitialStartRow(self: *Self, size: terminal.TerminalSize, cursor_pos: terminal.CursorPosition) !u16 {
        _ = self;
        const minimum_viewport_height = @min(size / 2, 24);

        // Calculate available space below cursor
        const available_rows = size.rows - (cursor_pos.row - 1) - 1;

        // If enough space below cursor, use current position
        if (available_rows >= minimum_viewport_height) {
            return cursor_pos.row;
        }

        // Otherwise, scroll up to make room
        const scroll_amount = minimum_viewport_height - available_rows;
        const new_row = size.rows - minimum_viewport_height;
        const cursor_col = cursor_pos.column;

        try scrollAndSetCursor(scroll_amount, new_row, cursor_col);
        return new_row;
    }

    // This function handles terminal size changes.
    pub fn updateBounds(self: *Self) !bool {
        // First check if terminal was cleared
        const cursor_updated = self.handleClear() catch false;

        // Store current height for comparisons
        const previous_rows = self.terminal_size.rows;

        // Get new terminal size
        const new_size = terminal.getTerminalSize();

        // If height has'nt changed, only return cursor update status
        if (new_size.rows == previous_rows) {
            return cursor_updated;
        }

        // Update to new size and adjust viewport
        self.terminal_size = new_size;
        try self.updateStartRow(new_size.rows, previous_rows);
        self.updateVisibleRows();
        return true;
    }

    // This Function adjusts start row after resize.
    pub fn updateStartRow(self: *Self, new_rows: u16, previous_rows: u16) !void {
        // If viewport starts at top, no adjustment needed
        if (self.viewport_start == 1) return;

        const previous_start = self.viewport_start;

        // Determines how much viewport space remains after accounting for the viewport's starting position.
        const available_rows = new_rows -| self.viewport_start -| 2;

        // Handle terminal shrinking
        if (new_rows <= previous_rows and available_rows < self.visible_rows) {
            // Move viewport to top if not enough space
            self.viewport_start = 1;
            try setCursor(1, 1);

            // Handle terminal growing
        } else if (new_rows >= previous_rows) {
            // Move viewport down proportionally
            self.viewport_start += new_rows - previous_rows;

            try scrollAndSetCursor(self.viewport_start - previous_start, // Lines to scroll
                self.viewport_start, // Move to row 10
                1 // column 1
            );
        }
    }

    // This Function handles terminal clear operations.
    pub fn handleClear(self: *Self) !bool {
        const cursor_pos = try terminal.getCursorPosition();

        // If cursor is'nt at row 1, no clear happened
        if (cursor_pos != 1) {
            return false;
        }

        self.viewport_start = cursor_pos.row;
        self.updateVisibleRows();

        return true;
    }

    pub fn updateVisibleRows(self: *Self) void {
        self.visible_rows = self.terminal_size.rows - (self.viewport_start - 1) - 1;
    }

    // Cursor Control Functions

    pub fn scrollAndSetCursor(lines: u16, row: u16, col: u16) !void {
        var buffer: [64]u8 = undefined;

        // Create escape sequence for scrolling and cursor positioning
        // Scroll up and set cursor position
        const command = try std.fmt.bufPrint(&buffer, "\x1b[{d}S\x1b[{d},{d}H", .{ lines, row, col });
        _ = try posix.write(posix.STDERR_FILENO, command);
    }

    pub fn setCursor(row: u16, col: u16) !void {
        var buffer: [64]u8 = undefined;

        const command = try std.fmt.bufPrint(&buffer, "\x1b[{d},{d}H", .{ row, col });
        _ = try posix.write(posix.STDERR_FILENO, command);
    }
};
