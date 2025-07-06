const std = @import("std");
const posix = std.posix;

// Represents terminal dimensions with columns and rows
// Using u16 maintains compatability with underlying system calls
// columns: Number of columns (character per line)
// rows: Number of visible lines
pub const TerminalSize = struct {
    rows: u16,
    columns: u16,
};

// Represents cursor position in the terminal
// column: column position (1-based indexing)
// row: row position (1-based indexing)
pub const CursorPosition = struct {
    column: u16,
    row: u16,
};

// Terminal reporting modes (used in VT100 terminal operations)
// ref: https://vt100.net/docs/vt510-rm/DECRPM.html
pub const ReportMode = enum {
    not_recognized,
    set,
    reset,
    permanently_set,
    permanently_reset,
};

// Queries and returns the current terminal window dimensions.
// Using POSIX ioctl call to get window size information.

// @returns: TerminalSize struct containing columns and rows
pub fn getTerminalSize() TerminalSize {
    var ws: posix.winsize = undefined;
    // posix.STDERR_FILENO is the standard error file descriptor (typically 2)
    _ = posix.system.ioctl(posix.STDERR_FILENO, posix.T.IOCGWINSZ, &ws);
    return TerminalSize{ .columns = ws.col, .rows = ws.row };
}

// Queries the current terminal position in the terminal.
// Sends ANSI escape sequence and parses the response.
// @returns: CursorPosition containing current cursor location
// @error: Returns error if response format is invalid
pub fn getCursorPosition() !CursorPosition {
    // Send query sequence to get cursor position
    // posix.write writes data to the file descriptor.
    // ANSI escape sequence "\x1b[6n":
    // \x1b is the escape character
    // [6n is the Device status report (DSR) command.
    // This sequence asks the terminal "what is the cursor position?"
    // The terminal responds with" "\x1b[{row};{column}R"
    _ = try posix.write(posix.STDERR_FILENO, "\x1b[6n");

    var buff: [64]u8 = undefined;
    // Read the response from terminal
    // posix.STDERR_FILENO is the standard input file descriptor (typically 0)
    const len = try posix.read(posix.STDIN_FILENO, &buff);

    if (!isCursorPosition(buff[0..len])) {
        return error.InvalidResponse;
    }

    // Parse Response format: ESC[row;colR
    // Example response might be "\x1b[24;80R" (row 24, col 80)

    // Parse numbers from response
    var row: [8]u8 = undefined;
    var col: [8]u8 = undefined;
    var ridx: u3 = 0;
    var cidx: u3 = 0;
    var is_parsing_cols = false;

    // Skip first 2 characters and parse until 'R'
    for (2..(len - 1)) |i| {
        const b = buff[i];

        if (b == ';') {
            is_parsing_cols = true;
            continue;
        }

        if (b == 'R') break;

        if (is_parsing_cols) {
            // When processing after semicolon (;)
            col[cidx] = buff[i]; // Store digits in column buffer
            cidx += 1;
        } else {
            // When processing before semicolon (;)
            row[ridx] = buff[i]; // Store digits in row buffer
            ridx += 1;
        }
    }

    // Convert string numbers to integers
    return CursorPosition{
        .column = try std.fmt.parseInt(u16, col[0..cidx], 10),
        .row = try std.fmt.parseInt(u16, row[0..ridx], 10),
    };
}

// Validates if a buffer contains a valid cursor position response
pub fn isCursorPosition(buff: []u8) bool {
    if (buff.len < 6) return false;
    if (buff[0] != 27 or buff[1] != '[') return false;
    return true;
}

// Enables raw mode for terminal input processing.
// Configures terminal for character-by-character input without echo.
//
// In Normal Mode: Terminal waits for Enter key before processing input
// In Raw Mode:    Terminal processes each keystroke immediately.
//
// @param original_settings: Pointer to store original terminal settings
// RAW mode configuration:
// - Disables IXON: Software flow control
// - Disables ICRNL: CR to NL translation
// - Disables IEXTEN: Extended input processing
// - Disables ICHO: Input echo
// - Disables ICANON: Canonical mode
// - Enables ISIG: Signal generation
pub fn enableRawMode(original_settings: *posix.termios) !void {
    // Get current terminal attributes/settings
    var terminal_config = try posix.tcgetattr(posix.STDIN_FILENO);
    // Backup original settings for later restoration
    original_settings.* = terminal_config;

    // Modify input flags
    terminal_config.iflag.IXON = false; // Disable start/stop flow control
    terminal_config.iflag.ICRNL = false; // Disable CR to NL translation

    // Modify local flags
    // Echo means displaying typed characters on screen
    // When disabled, typed characters are'nt automatically displayed
    terminal_config.lflag.ECHO = false; // Disable input echo
    terminal_config.lflag.ICANON = false; // Disable canonical mode
    terminal_config.lflag.IEXTEN = false; // Disable extended input processing

    terminal_config.lflag.ISIG = true; // Enable signals

    // Apply new settings
    try posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.FLUSH, terminal_config);
}

// Restores terminal settings to original state.
// @param originalSettings: pointer to stored original terminal settings.
pub fn disableRawMode(originalSettings: *posix.termios) !void {
    try posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.FLUSH, originalSettings.*);
}

// Checks if terminal supports synchronized output
pub fn canSynchronizeOutput() !bool {
    // Send query to check if terminal supports synchronized output
    _ = try posix.write(posix.STDERR_FILENO, "\x1b[?2026$p");

    var buff: [64]u8 = undefined;
    const len = try posix.read(posix.STDIN_FILENO, &buff);

    // Check if response starts with expected sequence and is long enough
    if (!std.mem.eql(u8, buff[0..len], "\x1b[?2026;") or len < 9) return false;

    // Check if terminal reports this feature as available
    return getReportMode(buff[8]) == .reset;
}

// Converts terminal response to ReportMode enum.
// @param char: character from terminal response
// @returns corresponding ReportMode value
pub fn getReportMode(char: u8) ReportMode {
    return switch (char) {
        '0' => ReportMode.not_recognized,
        '1' => ReportMode.set,
        '2' => ReportMode.reset,
        '3' => ReportMode.permanently_set,
        '4' => ReportMode.permanently_reset,
        else => ReportMode.not_recognized,
    };
}
