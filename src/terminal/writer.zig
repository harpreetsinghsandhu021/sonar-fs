const std = @import("std");
const Allocator = std.mem.Allocator;

// Synchronization protocol
// CSI(Control Sequence Introducer) and DCS(Device Control String) are two types of escape sequences used in terminals.
//
// CSI is a type of sequence that starts with character \x1b[(ESC + [). It is used to introduce a
// control sequence that can be used to control the cursor position, text formatting and other terminal settings.
// CSI sequences are mainly used for:
// - Move the cursor to a specific position on the screen.
// - Change the text color or background color.
// - Enable or disable bold, italic, or underline text.
//  - Clear the screen or portion of the screen.
// - Set the cursor shape or blink rate.
//
// DCS is a type of escape sequence that starts with characters \x1bP(ESC + P). It is used to introduce a
// device control string that can be used to control terminal's settings and behavior.
// DCS sequences are mainly used for:
// - Set the terminal's title or icon name.
// - Enable or disable the terminal's scroll bar.
// - Set the terminal's font or size.
// - Enable or disable the terminal's mouse tracking.
const SyncProtocol = enum {
    none,
    csi, // Control Sequence Introducer
    dcs, // Device Control String
};

// Terminal output buffer implementation. Provides buffered writing capabilities for terminal
// output with synchronized update support.
pub const BufferedWriter = struct {
    allocator: Allocator,
    writer: std.fs.File.Writer, // The underlying `fileWriter` that writes to the stdout.
    buffer: []u8, // Main output buffer
    format_buffer: []u8, // Formatting buffer for print operations
    current_position: usize, // Current position in buffer
    is_buffering_enabled: bool, // Buffer mode toggle
    sync_protocol: SyncProtocol, // Synchronization protocol settings

    const Self = @This();

    pub const Writer = std.io.Writer(*Self, std.fs.File.Writer.Error, writeAny);

    pub fn init(allocator: Allocator, buffer_size: usize) !Self {
        return Self{
            .allocator = allocator,
            .writer = std.io.getStdErr().writer(),
            .buffer = try allocator.alloc(u8, buffer_size),
            .format_buffer = try allocator.alloc(u8, buffer_size),
            .current_position = 0,
            .is_buffering_enabled = false,
            .sync_protocol = .none,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.allocator.free(self.format_buffer);
    }

    // Flushes Buffered content to the terminal.
    pub fn flush(self: *Self) !void {
        if (self.current_position == 0) return;

        // If synchronized output is enabled, write the synchronization sequence to the terminal.
        if (self.sync_protocol == .csi or self.sync_protocol == .dcs) {
            try self.writeSyncEnd();
        }

        // Write the buffer contents to the terminal using underlying filewriter.
        try self.writer.writeAll(self.buffer[0..self.current_position]);
        self.current_position = 0; // Reset the current position since buffer is flushed.
    }

    // Enables buffered output mode
    pub fn enableBuffering(self: *Self) !void {
        self.is_buffering_enabled = true;
        if (self.sync_protocol == .csi or self.sync_protocol == .dcs) {
            try self.writeSyncStart();
        }
    }

    // Disables buffered output mode
    pub fn disableBuffering(self: *Self) void {
        self.is_buffering_enabled = false;
    }

    // Writes synchronization start sequence based on protocol
    fn writeSyncStart(self: *Self) !void {
        // sequence code to enable Synchronized output in terminal.
        const sequence = switch (self.sync_protocol) {
            .csi => "\x1b[?2026h", // `?` is private mode indicator.
            // 2026 is parameter for "sync output" mode. `h` is the mode indicator to enable the feature.
            .dcs => "\x1bP=1s\x1b\\", // `=1` parameter to enable synchronized output, `s` is the terminator for DCS sequence
            // `\x1b\\` is the string terminator.
            .none => return,
        };

        try self.writeToBuffer(sequence);
    }

    // Writes synchronization end sequence based on protocol
    fn writeSyncEnd(self: *Self) !void {
        const sequence = switch (self.sync_protocol) {
            .csi => "\x1b[?2026l",
            .dcs => "\x1bP=2s\x1b\\",
            .none => return,
        };

        try self.writeToBuffer(sequence);
    }

    // Copies bytes to internal buffer.
    fn writeToBuffer(self: *Self, bytes: []const u8) !void {
        const new_position = self.current_position + bytes.len;
        if (new_position > self.buffer.len) {
            return error.BufferOverflow;
        }

        @memcpy(self.buffer[self.current_position..new_position], bytes);
        self.current_position = new_position;
    }

    // Writes data to the output
    pub fn writeAny(self: *Self, bytes: []const u8) !usize {
        if (self.is_buffering_enabled) {
            return try self.writeBuffered(bytes);
        } else {
            return try self.writeImmediate(bytes);
        }
    }

    // Handles buffered writing with overflow protection
    fn writeBuffered(self: *Self, bytes: []const u8) !usize {
        // Check if new data would exceed buffer capacity
        if (self.current_position + bytes.len > self.buffer.len) {
            // Buffer would overflow, so flush current contents
            try self.flush();

            // If incoming data still exceeds buffer capacity, write it directly to avoid buffer overflow
            if (bytes.len > self.buffer.len) {
                return self.writer.write(bytes);
            }
        }

        // Copy new data to buffer
        try self.writeToBuffer(bytes);
        return bytes.len;
    }

    // Writes directly to output without buffering
    fn writeImmediate(self: *Self, bytes: []const u8) !usize {
        return try self.writer.write(bytes);
    }

    // Formatted printing with optional buffering
    pub fn print(self: *Self, comptime format: []const u8, args: anytype) !usize {
        if (self.is_buffering_enabled) {
            return try self.printBuffered(format, args);
        } else {
            return try self.printImmediate(format, args);
        }
    }

    // Handles buffered formatted printing
    fn printBuffered(self: *Self, comptime format: []const u8, args: anytype) !usize {
        return self.formatAndWrite(format, args, true);
    }

    // Handles immediate formatted printing
    fn printImmediate(self: *Self, comptime format: []const u8, args: anytype) !usize {
        return self.formatAndWrite(format, args, false);
    }

    // Internal helper for formatted printing.
    // Handles formatting of strings and their buffered or immediate output.
    fn formatAndWrite(self: *Self, comptime format: []const u8, args: anytype, use_buffer: bool) !usize {
        // Create a fixed buffer stream for formatting
        var format_stream = std.io.fixedBufferStream(self.format_buffer);
        // Format the string with arguments into the format buffer
        try std.fmt.format(format_stream.writer(), format, args);
        // Get the formatted result
        const formatted_bytes = format_stream.getWritten();
        // Write using buffered or immediate mode
        if (use_buffer) {
            return try self.writeBuffered(formatted_bytes);
        } else {
            return try self.writeImmediate(formatted_bytes);
        }
    }
};
