const std = @import("std");
const app = @import("../app/index.zig");
const owner = @import("../fs/ownerLookup.zig");
const Entry = @import("../fs/fsIterator.zig").Entry;
const ViewManager = @import("../view/viewManager.zig").ViewManager;
const Draw = @import("../terminal/draw.zig").Draw;

const Allocator = std.mem.Allocator;
const IndentList = std.ArrayList(bool);

// Configuration for File information display
const DisplayInfo = struct {
    show_icons: bool = true, // Show file type icons
    show_size: bool = true, // Show file size
    show_permissions: bool = false, // Show file permissions
    show_timestamp: bool = true, // Show time information
    show_modified: bool = true, // Show last modified time
    show_changed: bool = false, // Show last changed time
    show_accessed: bool = false, // Show last accessed time
    show_symlinks: bool = true, // Show symbolic link targets
    show_group: bool = false, // Show group ownership
    show_user: bool = false, // Show user ownership
    show_metadata: bool = true, // Master toggle for all metadata
};

// Tree is responsible for formatting values to output strings.
// It handles the visual representation of a file system structure.
const Tree = struct {
    output_buffer: [2048]u8, // output buffer for content
    style_buffer: [2048]u8, // Buffer for styling information
    allocator: Allocator,
    tree_structure: *IndentList, // Tracks Parent-child relationship
    display_config: DisplayInfo,
    group_names: *owner.UserMap,
    user_names: *owner.UserMap,

    const Self = @This();

    pub fn init(allocator: Allocator, config: app.Config) !Self {
        const tree_structure = try allocator.create(IndentList);
        tree_structure.* = IndentList.init(allocator);

        const group_names = try allocator.create(owner.UserMap);
        group_names.* = owner.UserMap.init(allocator);

        const user_names = try allocator.create(owner.UserMap);
        user_names.* = owner.UserMap.init(allocator);

        return Self{
            .tree_structure = tree_structure,
            .allocator = allocator,
            .output_buffer = undefined,
            .style_buffer = undefined,
            .display_config = DisplayInfo{
                .show_icons = config.icons,
                .show_size = config.size,
                .show_permissions = config.perm,
                .show_timestamp = config.time,
                .show_symlinks = config.link,
                .show_modified = config.time_type == .modified,
                .show_accessed = config.time_type == .accessed,
                .show_changed = config.time_type == .changed,
                .show_metadata = config.icons or config.size or config.perm or config.time or config.link,
            },
            .group_names = group_names,
            .user_names = user_names,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tree_structure.deinit();
        self.allocator.destroy(self.tree_structure);

        self.group_names.deinit();
        self.allocator.destroy(self.group_names);

        self.user_names.deinit();
        self.allocator.destroy(self.user_names);
    }

    // Updates the tree structure to track parent-child relationships and sibling connections.
    // This information is used to draw the correct tree branch characters.
    fn updateTreeStructure(self: *Self, file_entry: *Entry) !void {
        // Store whether the current depth level had previous items with siblings.
        // This helps maintain continous lines in the tree structure
        var previous_has_sibling: bool = false;

        // Check if we need to expand our tree structure array.
        // E.g If we're processing an entry at depth 3 but our array is only size 2.
        if (file_entry.depth >= self.tree_structure.items.len) {
            // Resize the array to accomodate the new depth
            // Example:[false, false] => [false, false, false, false]
            try self.tree_structure.resize(file_entry.depth + 1);
        } else {
            // If we already have an entry at this depth, preserve its state.
            // This maintains vertical lines for parallel branches
            previous_has_sibling = self.tree_structure.items[file_entry.depth];
        }

        // Update the tree structure for current depth
        // An entry needs a connecting line (true) if:
        // 1. If it's not the last item (!file_entry.last), AND
        // 2. Either:
        //    - It's the first item in the group (file_entry.first) OR
        //    - Previous items at this depth had siblings (previous_has_sibling)
        self.tree_structure.item[file_entry.depth] = !file_entry.last and (file_entry.first or previous_has_sibling);
    }

    // Resets the tree structure for a new rendering pass.
    fn resetTreeStructure(self: *Self) void {
        for (0..self.tree_structure.items.len) |depth| {
            self.tree_structure.items[depth] = false;
        }
    }

    // Generates the visual indentation characters that create the vertical structure of the tree.
    // Each level of depth can have either a vertical line "|   " or "     "
    fn generateIndentationLines(self: *Self, file_entry: *Entry, buffer: []u8) []u8 {
        var buffer_position: usize = 0; // Tracks where we are in the buffer as we build the indentation string

        for (0..file_entry.depth) |current_depth| {
            const indentChar = if (self.tree_structure.items[current_depth]) "│   " else "    ";

            // Copy the chosen indentation char to the buffer.
            // This builds the indentation string one level at a time
            @memcpy(buffer[buffer_position .. buffer_position + indentChar.len], indentChar);
            buffer_position += indentChar.len;
        }

        return buffer[0..buffer_position];
    }

    // Creates the branch connector for the current item.
    fn generateBranchConnector(self: *Self, file_entry: *Entry, buffer: []u8) ![]u8 {
        // First add the indentation lines
        var total_length = self.generateIndentationLines(file_entry, buffer).len;

        // Add the appropriate branch connector
        const branch_char = if (file_entry.last) "└──" else "├──";
        @memcpy(buffer[total_length .. total_length + branch_char.len], branch_char);
        total_length += branch_char.len;

        return buffer[0..total_length];
    }

    // fn displayFileLine(self: *Self, file_index: usize, view: *const ViewManager, draw: *Draw){}
};
