const std = @import("std");
const app = @import("../app/index.zig");
const owner = @import("../fs/ownerLookup.zig");
const Entry = @import("../fs/fsIterator.zig").Entry;
const ViewManager = @import("../view/viewManager.zig").ViewManager;
const iconManager = @import("../app/ui/iconManager.zig");
const Draw = @import("../terminal/draw.zig").Draw;
const terminal_styles = @import("../terminal/styles.zig");
const stat = @import("../fs/stat.zig");
const fmt = @import("../view/fmt.zig");
const icons = @import("../app/ui/icons.zig").icons;

const string_utils = @import("../utils/string.zig");

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

// Holds maximum widths for metadata fields
const MetadataWidths = struct {
    group_width: usize,
    user_width: usize,
};

// Tree is responsible for formatting values to output strings.
// It handles the visual representation of a file system structure.
pub const Tree = struct {
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

        owner.deinitUserMap(self.group_names);
        self.allocator.destroy(self.group_names);

        owner.deinitUserMap(self.user_names);
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

    fn displayFileLine(self: *Self, file_index: usize, view: *const ViewManager, display: *Draw) !void {
        // Clear existing line content
        try display.clearLine();

        var file_entry = view.buffer.items[file_index];

        // Check if we should show metadata (permissions, size, etc.)
        const show_prefix_info = self.display_config.show_metadata and
            (self.display_config.show_permissions or
                self.display_config.show_size or
                self.display_config.show_user or
                self.display_config.show_group or
                self.display_config.show_timestamp);

        // Display File permissions if enabled
        if (self.display_config.show_metadata and self.display_config.show_permissions) {
            const file_stat = try file_entry.item.getStat();
            const permission_string = try fmt.mode(file_stat, &self.output_buffer);
            try display.printString(permission_string, .{ .no_style = true });
        }

        // Display File size if enabled
        if (self.display_config.show_metadata and self.display_config.show_size) {
            const file_stat = try file_entry.item.getStat();
            const size_string = try fmt.size(file_stat, &self.output_buffer);
            try display.printString(size_string, .{ .fg = .cyan });
        }

        // Display ownership information
        try self.displayOwnershipInfo(file_entry, display, MetadataWidths);

        // Show timstamp if enabled
        if (self.getTimeDisplayType()) |time_type| {
            const file_stat = try file_entry.item.getStat();
            const time_string = fmt.time(file_stat, time_type, &self.output_buffer);
            try display.printString(time_string, .{ .fg = .yellow });
        }

        // Add spacing after metadata if present
        if (show_prefix_info) {
            try display.printString(" ", .{ .no_style = true });
        }

        // Display tree structure and file name
        try self.displayTreeAndFileName(file_entry, file_index, view, display);
    }

    // Displays user and group ownership information
    fn displayOwnershipInfo(self: *Self, file_entry: *Entry, display: *Draw, metadata_widths: *const MetadataWidths) !void {
        if (self.display_config.show_metadata) {
            if (self.display_config.show_user) {
                const file_stat = try file_entry.item.getStat();
                const user_name = string_utils.rightPadding(try file_stat.getUsername(self.user_names), metadata_widths.user_width + 1, ' ', &self.output_buffer);
                try display.printString(user_name, .{ .fg = .blue });
            }

            if (self.display_config.show_group) {
                const file_stat = try file_entry.item.getStat();
                const group_name = string_utils.rightPadding(try file_stat.getGroupname(self.group_names), metadata_widths.group_width + 1, ' ', &self.output_buffer);
                try display.printString(group_name, .{ .fg = .green });
            }
        }
    }

    // Displays the tree structure, file name, and additional file information
    fn displayTreeAndFileName(self: *Self, file_entry: *Entry, file_index: usize, view: *const ViewManager, display: *Draw) !void {
        // 1. Display Branch Tree structure
        const branch_chars = self.generateBranchConnector(file_entry, &self.output_buffer);
        try display.printString(branch_chars, .{ .faint = true });

        // 2. Display File icon if enabled
        if (self.display_config.show_icons) {
            const icon = try iconManager.getIcon(file_entry);
            const file_color = try getFileColor(file_entry, false);

            try display.printString(icon, .{ .fg = file_color });
            try display.printString(" ", .{ .no_style = true });
        }

        // 3. Display Filename with appropriate formatting
        try displayFilename(file_entry, file_index, view, display);

        // 4. Display symlink target if applicable
        try self.displaySymLinkIfPresent(file_entry, display);

        // 5. Display cursor indicator if this is selected file
        if (view.cursor_pos == file_index) {
            try display.printString(" <", .{ .bold = true, .fg = .magenta });
        }

        try display.printString(" ", .{ .no_style = true });
    }

    // Gets the type of timestamp to display
    fn getTimeDisplayType(self: *Self) ?stat.timeType {
        if (!self.display_config.show_metadata or !self.display_config.show_timestamp) {
            return null;
        }

        return if (self.display_config.show_modified) .modified else if (self.display_config.show_accessed) .accessed else if (self.display_config.show_changed) .changed else .modified;
    }

    // Displays the File name
    fn displayFilename(file_entry: *Entry, file_index: usize, view: *const ViewManager, display: *Draw) !void {
        const file_name = file_entry.item.getBasename();
        const file_color = try getFileColor(file_entry, view.cursor_pos == file_index);
        try display.printString(file_name, .{ .fg = file_color, .underline = file_entry.selected });
    }

    // Displays symlink target if file is a symbolic link
    fn displaySymLinkIfPresent(self: *Self, file_entry: *Entry, display: *Draw) !void {
        if (self.display_config.show_symlinks and file_entry.item.isLink()) {
            const link_target = try std.posix.readlink(file_entry.item.getAbsolutePath(), &self.output_buffer);

            // Display arrow symbol and link target
            const arrow = if (self.display_config.show_icons)
                "" ++ icons.arrow_right ++ ""
            else
                " -> ";

            try display.printString(arrow, .{ .no_style = true });
            try display.printString(link_target, .{ .fg = .red });
        }
    }

    // Determine the appropriate color for a file based on its type
    fn getFileColor(file_entry: *Entry, is_selected: bool) !terminal_styles.Color {
        if (is_selected) return .magenta;

        const file_stat = try file_entry.item.getStat();

        if (file_stat.isDir()) return .blue;
        if (file_stat.isLinkFile()) return .cyan;
        if (file_stat.isExecutable()) return .green;
        if (file_stat.isCharSpecialFile()) return .yellow;
        if (file_stat.isBlockFile()) return .yellow;

        return .default;
    }

    // Prints Multiple lines of the tree view handling cursor positioning.
    pub fn printLines(self: *Self, view: *ViewManager, display: *Draw, start_row: usize, is_command_mode: bool) !void {
        // Reset tree structure for new rendering pass
        self.resetTreeStructure();
        // Position cursor at start of display area
        try display.moveCursor(start_row, 0);

        // Calculate maximum lengths for user/group names if needed
        var metadata_widths = MetadataWidths{ .group_width = 0, .user_width = 0 };
        if (self.display_config.show_metadata and (self.display_config.show_group or self.display_config.show_user)) {
            try self.calculateMetadataWidths(view, &metadata_widths);
        }

        // Process each item in the view buffer
        for (0..(view.viewport_end + 1)) |current_index| {
            const file_entry = view.buffer.items[current_index];

            // Update tree structure for current entry
            try self.updateTreeStructure(file_entry);

            if (current_index > view.viewport_end) {
                break;
            }

            if (current_index < view.viewport_start) {
                continue;
            }

            // Check if this is the last item during command mode
            const is_last_item = is_command_mode and view.viewport_end == current_index;

            // Always render during refresh
            if (view.needs_full_redraw) {
                try self.displayFileLine(current_index, view, display);

                // Special handling for last item in command mode. This ensures the last item is properly rendered before showing the command prompt.
                // The cursor needs to be positioned correctly after the last item.
            } else if (current_index == view.cursor_pos or current_index == view.previous_cursor or is_last_item) {
                // Move cursor to correct position for these lines
                const row = start_row + (current_index - view.viewport_start);
                try display.moveCursor(row, 0);
                try self.displayFileLine(current_index, view, display);
            }
        }

        // Reset full refresh flag
        view.needs_full_redraw = false;
    }

    // Calculates maximum widths needed for user and group names
    fn calculateMetadataWidths(self: *Self, view: *ViewManager, widths: *MetadataWidths) !void {
        // Iterate through visible items to find longest names
        for (view.viewport_start..view.viewport_end + 1) |i| {
            const file_entry = view.buffer.items[i];
            const file_stat = try file_entry.item.getStat();

            if (self.display_config.show_group) {
                const group_name = try file_stat.getGroupname(self.group_names);
                widths.group_width = @max(widths.group_width, group_name.len);
            }

            if (self.display_config.show_user) {
                const user_name = try file_stat.getUsername(self.user_names);
                widths.user_width = @max(widths.user_width, user_name.len);
            }
        }
    }
};
