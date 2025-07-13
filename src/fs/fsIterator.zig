const std = @import("std");
const Allocator = std.mem.Allocator;
const FileDir = @import("fileDir.zig").FileDir;

// Represents each item in the iteration.
pub const Entry = struct {
    item: *FileDir, // Actual item being traversed
    depth: usize, // How deep the item is in the tree
    first: bool, // Whether this is the first child in its parent's children
    last: bool, // Whether this is the last child in its parent's children
    selected: bool = false,
};

const EntryList = std.ArrayList(*Entry);

// This function constructs an Entry struct with the given values.
pub fn getEntry(index: usize, parent_depth: usize, children: std.ArrayList(*FileDir), skipCount: usize) Entry {
    return Entry{
        .item = children.items[index],
        .depth = parent_depth + 1,
        .first = (index -| skipCount) == 0,
        .last = index == children.items.len -| (1 + skipCount),
    };
}

// Implements tree traversal using a stack-based approach.
pub const Iterator = struct {
    // Controls how deep the integration goes
    // -1: Go as deep as possible
    // -2: Only expand if children are present
    //  0: Don't expand (just current level)
    //  n: Expand until depth 'n'
    iterMode: i32 = -1,
    stack: EntryList,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, first: *FileDir, iterMode: i32) !Self {
        var stack = EntryList.init(allocator);
        const entry = try allocator.create(Entry);
        entry.* = .{
            .item = first,
            .depth = 0,
            .first = true,
            .last = true,
        };

        try stack.append(entry);

        return Self{
            .iterMode = iterMode,
            .stack = stack,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.items) |entry| {
            self.allocator.destroy(entry);
        }

        self.stack.deinit();
    }

    // This function implements depth-first traversal using a stack-based approach.
    //
    // This function provides a way to traverse through the file system tree one at a time.
    pub fn next(self: *Self) ?*Entry {
        if (self.stack.items.len == 0) return null;

        const last_item = self.stack.pop();
        // If an item was popped, grow the stack with its children
        if (last_item) |item| {
            try self.insertIntoStack(item);
        }

        return last_item;
    }

    // This function handles the following operations:
    // Controls how deep the traversal goes
    // Manages what items are included/excluded
    // Ensures proper ordering of traversal
    // Maintains the stack that drives the iteration process
    // Handles memory allocation for new entries
    pub fn insertIntoStack(self: *Self, entry: *Entry) !void {
        // Early return checks
        // Checks invalid iterModes
        if (self.iterMode < -2) return;
        // Must have children at itermode -2
        if (self.iterMode == -2 and !entry.item.hasChildren()) return;
        // Respects Depth limits
        if (self.iterMode >= 0 and entry.depth > self.iterMode) return;
        // Must be a directory
        if (!entry.item.isDir()) return;

        const children = try entry.item.getChildren();

        // Process child in reverse order. This is because Stack is LIFO (Last in, First out)
        for (0..children.items.len) |i| {
            const reverse_index = children.items.len - 1 - i;

            const childEntry = try self.allocator.create(Entry);
            childEntry.* = getEntry(reverse_index, entry.depth, children, 0);

            try self.stack.append(childEntry);
        }
    }
};
