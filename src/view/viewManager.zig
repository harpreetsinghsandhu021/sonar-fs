const std = @import("std");
const Allocator = std.mem.Allocator;

const Entry = @import("../fs/fsIterator.zig").Entry;
const Iterator = @import("../fs/fsIterator.zig").Iterator;

// View Manager handles the display window of a file system explorer.
// It maintains a buffer of visible items and manages viewport boundaries
// through first/last indices and cursor position.
pub const ViewManager = struct {
    allocator: Allocator,
    // Buffer contains pointers to entry items that are being currently displayed.
    // This may contain more items than currently visible.
    buffer: std.ArrayList(*Entry),
    // Index of first visible item in the viewport. Represents the top boundary of visible area.
    viewport_start: usize,
    // Index of last visible item in the viewport. Represents the bottom boundary of visible area.
    viewport_end: usize,
    // Current cursor position within the buffer. Must be in the range of [first, last].
    cursor_pos: usize,
    // Previous cursor position, used to optimize redrawing
    previous_cursor: usize,
    // Flag indicating whether entire viewport needs redrawing. True when viewport boundaries change
    // or content shifts.
    needs_full_redraw: bool,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = std.ArrayList(*Entry).init(allocator),
            .viewport_start = 0,
            .viewport_end = 0,
            .cursor_pos = 0,
            .previous_cursor = 0,
            .needs_full_redraw = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    // Updates the viewport state based on cursor movement and available space.
    // This is the main function for maintaining proper view state.
    //
    // This function ensures:
    // 1. Cursor stays within visible range when scrolling.
    // 2. Viewport boundaries remain valid
    // 3. Buffer contains necessary items
    // 4. Proper redraw flags are set
    pub fn update(self: *Self, iter: *Iterator, maxRows: u16) !void {
        const prevStart = self.viewport_start;
        const prevEnd = self.viewport_end;

        // If we`re at the start, ensure the view boundaries are correct.
        if (self.viewport_start == 0) {
            try self.correct(maxRows, iter);
        }

        // The loop ensures the cursor stays visible.
        while (true) {
            if (self.cursor_pos > self.viewport_end) {
                try self.scrollViewportUp(iter);
            } else if (self.cursor_pos < self.viewport_start) {
                try self.scrollViewportDown(maxRows);
            } else {
                break;
            }
        }

        // Makes final adjustments to ensure boundaries are valid
        try self.correct(maxRows, iter);

        // Determines if the entire view needs to be redrawn
        self.updateRedrawStatus(prevStart, prevEnd);
    }

    // Ensures viewport boundaries and cursor position are valid.
    // Handles buffer size management and boundary corrections.
    //
    // Performs three main corrections:
    // 1. Ensures `viewport_end` index is valid relative to buffer size.
    // 2. Maintains proper `viewport_first` position.
    // 3. Ensures `cursor_pos` stays within viewport boundaries.
    fn correct(self: *Self, maxRows: u16, iter: *Iterator) !void {
        const viewport_size = self.viewport_end -| self.viewport_start; // Current view size
        const max_viewport_end = self.viewport_start + maxRows; // Maximum possible last index

        // Ensure buffer has enough items loaded
        try self.ensureBufferLen(max_viewport_end, iter);
        self.viewport_end = @min(max_viewport_end, self.buffer.items.len) - 1;

        // If we`re at the start of the viewport, no need for further corrections
        if (self.viewport_start == 0) {
            return;
        }

        // Maintains the viewport size by adjusting the first index based on last index.
        if (viewport_size > 0) {
            self.viewport_start = self.viewport_end -| viewport_size;
        }

        // Ensures cursor stays within view boundaries. If cursor is too high or low, clamps
        // it to the view boundaries.
        if (self.cursor_pos < self.viewport_start) {
            self.cursor_pos = self.viewport_start;
        } else if (self.cursor_pos > self.viewport_end) {
            self.cursor_pos = self.viewport_end;
        }
    }

    // Ensures buffer contains enough items for desired length. Loads additional items
    // from iterator if needed.
    //
    // @param len: Desired buffer length
    // @param iter: Iterator for loading additional items
    fn ensureBufferLen(self: *Self, len: usize, iter: *Iterator) !void {
        // No need to load additional items.
        if (self.buffer.items.len >= len) return;

        while (iter.next()) |entry| {
            try self.buffer.append(entry);
            if (self.buffer.items.len >= len) break;
        }
    }

    // Moves viewport indices forward (down) when cursor exceeds bottom boundary.
    // Handles three cases:
    // 1. More items are available in current buffer
    // 2. Need to load more items from iterator
    // 3. Reached end of available items
    fn scrollViewportUp(self: *Self, iter: *Iterator) !void {
        // If we have`nt reached the end of our loaded buffer, simply move both boundaries down by one.
        if (self.viewport_end < (self.buffer.items.len - 1)) {
            self.viewport_start += 1;
            self.viewport_end += 1;

            // If we`re at the end of buffer but iterator has more items
        } else if (iter.next()) |entry| {
            try self.buffer.append(entry);
            self.viewport_start += 1;
            self.viewport_end += 1;

            // Iterator has no more items, move cursor to last position
        } else {
            self.cursor_pos = self.viewport_end;
        }
    }

    // Moves viewport indices backward (up) when cursor moves above top boundary.
    // Handles two cases:
    // 1. Can expand view size if within `maxRows` limit.
    // 2. Maintain current view size by moving both boundaries.
    fn scrollViewportDown(self: *Self, maxRows: usize) !void {
        const viewport_size = self.viewport_end - self.viewport_start;

        if (viewport_size < maxRows and self.viewport_end - self.cursor_pos < maxRows) {
            self.viewport_start = self.cursor_pos;
        } else {
            self.viewport_start = self.cursor_pos;
            self.viewport_end = self.viewport_start + viewport_size;
        }
    }

    // Determines whether full viewport redraw is needed. Sets `needs_full_redraw` flag based
    // on boundaries changes.
    fn updateRedrawStatus(self: *Self, prev_start: usize, prev_end: usize) void {
        // Set flag if boundaries have changed
        self.needs_full_redraw = self.needs_full_redraw or (self.viewport_start != prev_start) or (self.viewport_end != prev_end);
        // Set flag if viewport size has changed
        self.needs_full_redraw = self.needs_full_redraw or (self.viewport_start - prev_start) != (self.viewport_end - prev_end);
    }
};
