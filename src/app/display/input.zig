// This module acts as the input handler for the application.
//
// It reads keyboard input from the terminal and translates it into meaningful actions that the application can understand and execute.

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const Capture = @import("./capture.zig");
const terminal = @import("../../terminal/terminal.zig");

// Create a scoped logger for this module to help with debugging.
const log = std.log.scoped(.input);

const InputReadError = error{
    EndOfStream,
    // Occurs when we recieve a cursor position from the terminal (this happens when terminal responds to cursor position queries)
    RecievedCursorPosition,
};

// All the possible actions that the application can perform
// These represents the `vocabulary` of commands the user can trigger.
pub const AppAction = enum {
    // Navigation actions - Moving around the file tree
    up,
    down,
    left,
    right,
    enter,
    quit,

    // Jump Navigation - Quickly move to specific positions
    top, // Jump to first item (like vim's `gg`)
    bottom, // Jump to the last item (like vim's `G`)

    // Depth control - expand tree to specific depths
    depth_one,
    depth_two,
    depth_three,
    depth_four,
    depth_five,
    depth_six,
    depth_seven,
    depth_eight,
    depth_nine,

    // Bulk Expanision controls
    expand_all,
    collapse_all,

    // Fold Navigation - Jump between collapsed/expanded sections
    prev_fold, // Jump to previous fold (like vim's `{`)
    next_fold, // Jump to previous fold (like vim's `}`)

    // File Operations
    change_root,
    open_item,
    change_dir,

    // Display Toggle action - show/hide different information columns
    toggle_info,
    toggle_icons,
    toggle_size,
    toggle_time,
    toggle_perm,
    toggle_link,
    toggle_group,
    toggle_user,

    // Time Display modes - Choose which timestamp to show
    time_modified,
    time_changed,
    time_accessed,

    dismiss_search,
    accept_search,
    update_search,
    dismiss_command,
    exec_command,

    no_action,
};

// Maps Keyboard input sequences to application actions
// This struct pairs a key sequence (what the user types) with the action it should trigger
const KeyBindingMap = struct {
    key_sequence: []const u8,
    triggered_action: AppAction,
};

// Complete list of all keyboard shortcuts and their corresponding actions
const input_key_mappings = [_]KeyBindingMap{
    // Basic Navigation - Both vim-style keys and arrow keys
    .{ .key_sequence = "k", .triggered_action = .up },
    .{ .key_sequence = "\x1b\x5b\x41", .triggered_action = .up }, // ANSI sequence
    .{ .key_sequence = "\x1b\x4f\x41", .triggered_action = .up }, // alternative sequence

    .{ .key_sequence = "j", .triggered_action = .down },
    .{ .key_sequence = "\x1b\x5b\x42", .triggered_action = .down },
    .{ .key_sequence = "\x1b\x4f\x42", .triggered_action = .down },

    .{ .key_sequence = "h", .triggered_action = .left },
    .{ .key_sequence = "\x1b\x5b\x44", .triggered_action = .left },
    .{ .key_sequence = "\x1b\x4f\x44", .triggered_action = .left },

    .{ .key_sequence = "l", .triggered_action = .right },
    .{ .key_sequence = "\x1b\x5b\x43", .triggered_action = .right },
    .{ .key_sequence = "\x1b\x4f\x43", .triggered_action = .right },

    // Activation
    .{ .key_sequence = "\x0d", .triggered_action = .enter },

    // Application Control
    .{ .key_sequence = "q", .triggered_action = .quit },
    .{ .key_sequence = "\x03", .triggered_action = .quit }, // Ctrl-C
    .{ .key_sequence = "\x04", .triggered_action = .quit }, // Ctrl-D

    // Numeric Depth expansion (1-9)
    .{ .key_sequence = "1", .triggered_action = .depth_one },
    .{ .key_sequence = "2", .triggered_action = .depth_two },
    .{ .key_sequence = "3", .triggered_action = .depth_three },
    .{ .key_sequence = "4", .triggered_action = .depth_four },
    .{ .key_sequence = "5", .triggered_action = .depth_five },
    .{ .key_sequence = "6", .triggered_action = .depth_six },
    .{ .key_sequence = "7", .triggered_action = .depth_seven },
    .{ .key_sequence = "8", .triggered_action = .depth_eight },
    .{ .key_sequence = "9", .triggered_action = .depth_nine },

    // Display Toggles
    .{ .key_sequence = "I", .triggered_action = .toggle_info },
    .{ .key_sequence = "i", .triggered_action = .toggle_icons },
    .{ .key_sequence = "s", .triggered_action = .toggle_size },
    .{ .key_sequence = "p", .triggered_action = .toggle_perm },
    .{ .key_sequence = "t", .triggered_action = .toggle_time },
    .{ .key_sequence = "tl", .triggered_action = .toggle_link },
    .{ .key_sequence = "g", .triggered_action = .toggle_group },
    .{ .key_sequence = "tm", .triggered_action = .time_modified },
    .{ .key_sequence = "ta", .triggered_action = .time_accessed },
    .{ .key_sequence = "tc", .triggered_action = .time_changed },
    .{ .key_sequence = "I", .triggered_action = .toggle_info },

    // Bulk Operations
    .{ .key_sequence = "E", .triggered_action = .expand_all },
    .{ .key_sequence = "C", .triggered_action = .collapse_all },

    // Fold Navigation
    .{ .key_sequence = "{", .triggered_action = .prev_fold },
    .{ .key_sequence = "}", .triggered_action = .next_fold },

    // Jump Navigation (gg-style)
    .{ .key_sequence = "gg", .triggered_action = .top },
    .{ .key_sequence = "G", .triggered_action = .bottom },

    // File Operations
    .{ .key_sequence = "R", .triggered_action = .change_root },
    .{ .key_sequence = "o", .triggered_action = .open_item },
    .{ .key_sequence = "cd", .triggered_action = .change_dir },
};

// The Main Input Handler structure
// This manages reading from stdin and maintaining capture state
pub const InputHandler = struct {
    stdin_reader: fs.File.Reader, // Reader for standard input
    input_buffer: [128]u8, // Buffer to store raw input bytes
    allocator: Allocator,
    search_capture: *Capture, // Handles search query input
    command_capture: *Capture, // Handles Command input

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const stdin_reader = std.io.getStdIn().reader();

        const search_capture = try allocator.create(Capture);
        search_capture.* = try Capture.init(allocator, .search);

        const command_capture = try allocator.create(Capture);
        command_capture.* = try Capture.init(allocator, .command);

        return Self{
            .stdin_reader = stdin_reader,
            .input_buffer = undefined, // Will be initialized when first used
            .search_capture = search_capture,
            .command_capture = command_capture,
        };
    }

    pub fn deinit(self: *Self) void {
        self.search_capture.deinit();
        self.allocator.destroy(self.search_capture);

        self.command_capture.deinit();
        self.allocator.destroy(self.command_capture);
    }

    // Read raw input bytes from stdin to the passed buffer.
    // This is a low-level function that handles the actual reading from the terminal.
    // @returns the slice of bytes that were read, or an error if something went wrong
    pub fn readRawInput(self: *Self, buffer: []u8) ![]u8 {
        const bytes_read = try self.stdin_reader.read(buffer);
        if (bytes_read == 0) {
            return InputReadError.EndOfStream;
        }

        // Check if what we read is a cursor position from the terminal.
        // This happens when the terminal responds to cursor position queries.
        // We need to filter these out because they are not user input.
        if (terminal.isCursorPosition(buffer[0..bytes_read])) {
            return InputReadError.RecievedCursorPosition;
        }

        return buffer[0..bytes_read];
    }

    // Main entry point for getting the next application action.
    // This function determines what mode we're in and routes to the appropriate handler.
    pub fn getNextAction(self: *Self) !AppAction {
        if (self.search_capture.is_capturing) {
            return self.handleSearchInput();
        }

        if (self.command_capture.is_capturing) {
            return self.handleCommandInput();
        }

        return self.processNormalInput();
    }

    // Handle keyboard event when in search mode.
    // In search mode, most keys are captured to build the search query, but special keys like enter and
    // escape have special feelings.
    fn handleSearchInput(self: *Self) !AppAction {
        // Try to read the next keystroke
        const input_slice = self.rawInput(self.input_buffer) catch |err| switch (err) {
            error.RecievedCursorPosition => return .no_action,
            error.EndOfStream => return .no_action,
            else => return err,
        };

        log.debug("search input recieved: {any}", .{input_slice});

        // Check for escape key (ASCII 27) - this cancels the search
        if (input_slice[0] == 27) {
            self.search_capture.stop(true);
            return .dismiss_search;
        }

        // Check for enter key (ASCII 13) - this accepts the search
        if (input_slice[0] == 13) {
            self.search_capture.stop(true);
            return .accept_search;
        }

        // For any othe key - add it to the search query
        try self.search_capture.capture(input_slice);
        return .update_search;
    }

    // Handle keyboard event when in command mode.
    // Similar to search mode, with slightly different behavior.
    // Commands are executed rather than searched.
    fn handleCommandInput(self: *Self) !AppAction {
        // Try to read the next keystroke
        const input_slice = self.rawInput(self.input_buffer) catch |err| switch (err) {
            error.RecievedCursorPosition => return .no_action,
            error.EndOfStream => return .no_action,
            else => return err,
        };

        // Check for escape key (ASCII 27) - this cancels the search
        if (input_slice[0] == 27) {
            self.command_capture.stop(true);
            return .dismiss_command;
        }

        // Check for enter key (ASCII 13) - this accepts the search
        if (input_slice[0] == 13) {
            self.command_capture.stop(false);
            return .exec_command;
        }

        return .no_action;
    }

    // Process keyboard input in normal mode (not search or command mode)
    // This is most complex function because it handles multi-character sequences and partial matches
    // that might need more characters to complete.
    fn processNormalInput(self: *Self) !AppAction {
        // Read the initial input
        var current_length = try self.stdin_reader.read(self.input_buffer);
        var current_slice = self.input_buffer[0..current_length];

        // Check if this is a cursor position response (ignore if so)
        if (terminal.isCursorPosition(current_slice)) {
            return .no_action;
        }

        // Temp buffer for manipulating input when we need to shift bytes.
        var temp_buffer: [128]u8 = undefined;

        // Main Processing Loop - keep trying to match input sequences
        while (true) {
            // Try to match against all known key bindings
            inline for (input_key_mappings) |key_mapping| {
                // Check for exact match - If we find one, we're done
                if (std.mem.eql(u8, key_mapping.key_sequence, current_slice)) {
                    return key_mapping.triggered_action;
                }

                // Check for partial match, this sequence could be the start of a longer one
                // For example, if we recieved "g" but the mapping is "gg", we need to wait for one more input.
                if (current_length < key_mapping.key_sequence.len and std.mem.eql(u8, key_mapping.key_sequence[0..current_length], current_slice)) {
                    // We have a partial match, so read more characters
                    current_length += try self.stdin_reader.read(self.input_buffer[current_slice.len..]);
                    current_slice = self.input_buffer[0..current_length];
                    break; // Start over with the new, longer input
                }
            } else {
                // If we get here, none of the key bindings matched
                // This could mean:
                // - The input is not a recognized command
                // - We have extra characters that don't belong to any sequence

                if (current_slice.len > 1) {
                    // We have multiple characters but no match
                    // Try removing the first character and see if the rest matches something
                    // This handles cases where we get spurious characters mixed with real input

                    current_length -= 1;

                    // Copy everything except the first character to out temp buffer
                    @memcpy(temp_buffer[0..current_length], self.input_buffer[1..(current_length + 1)]);
                    // Copy it back to the main buffer
                    @memcpy(self.input_buffer[0..current_length], temp_buffer[0..current_length]);

                    current_slice = self.input_buffer[0..current_length];
                } else {
                    // Single character that does'nt match anything - ignore it
                    return .no_action;
                }
            }
        }

        unreachable;
    }
};
