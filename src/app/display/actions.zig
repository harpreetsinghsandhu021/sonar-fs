//! APPLICATION ACTIONS MANAGER
//!
//! This file contains all the "actions" that can be executed within the file explorer.
//! Each public event in this file corresponds to a user-initiated event, such as pressing a key for navigation,
//! toggling a display option, or executing a command.
//!
//! These Functions typically take a pointer to the global state and modify it in some way.

const std = @import("std");
const State = @import("../../context/state.zig");
const Item = @import("../../fs/fsIterator.zig").Entry;
const SortType = @import("../../fs/sort.zig").SortType;
const SearchQuery = @import("../../utils/string.zig").SearchQuery;
const osUtils = @import("../../utils/os.zig");

const ascii = std.ascii;

// Moves the cursor up by one position in the file list.
pub fn moveCursorUp(state: *State) void {
    state.view.cursor_pos -|= 1;
}

// Moves the cursor down by one position in the file list.
pub fn moveCursorDown(state: *State) void {
    state.view.cursor_pos += 1;
}

// Jumps the cursor to the very first item in the list.
pub fn gotoTop(state: *State) void {
    state.view.cursor_pos = 0;
}

// Jumps the cursor to the very last item in the file list.
// This Function may need to load more items if they have'nt been loaded yet.
pub fn gotoBottom(state: *State) void {
    // Keep loading items from iterator until we reach the end.
    // This ensures we have all the items loaded before we reach the end.
    while (state.iterator.?.next()) |current_item| {
        state.view.buffer.append(current_item);
    }

    state.view.cursor_pos = state.view.buffer.items.len - 1;
}

// Navigates up to the parent directory or parent item in the tree.
// This handles both moving cursor to parent item and expanding parent directories.
pub fn navigateToParentItem(state: *State) !void {
    // Get the currently selected item under the cursor
    const current_item = state.getItemUnderCursor();

    // Check if the current item has a parent in the structure
    if (current_item.hasParent()) |parent_item| {
        // Try to find the parent's position in the current view buffer
        state.view.cursor_pos = state.getItemIndex(parent_item) catch |err| switch (err) {
            error.NotFound => state.view.cursor_pos,
            else => return err,
        };
    }
    // If the current item has no parent, we're at the root of current view.
    // Try to navigate up one directory level in the file system
    else if (try state.fs_manager.up()) |_| {
        // Successfully moved up a directory, reset cursor to top
        state.view.cursor_pos = 0;
        // rebuild view with new content
        state.needs_file_list_rebuild = true;
    }
}

// Navigates into a child directory or expands/collapses a folder.
pub fn navigateToChildItem(state: *State) !void {
    const current_item = state.getItemUnderCursor();

    // Check if the current item has children
    if (current_item.hasChildren()) {
        // Item has already loaded children, we need to rebuild the list
        state.needs_file_list_rebuild = true;
    } else {
        // Item does'nt have children loaded yet, try to toggle/load them.
        state.needs_file_list_rebuild = try toggleItemChildren(current_item);
    }

    // Only move cursor if we successfully made changes to the view
    if (!state.needs_file_list_rebuild) {
        return;
    }

    state.view.cursor_pos += 1;
}

// Toggles the children of an item.
//
// If the item has children, the function will free them. If the item does not have children,
// it tries to load them.
//
// @returns true if children loaded/toggled successfully.
pub fn toggleItemChildren(current_item: *Item) !bool {
    if (current_item.hasChildren()) {
        current_item.freeChildren(null);
        return true;
    }

    _ = current_item.getChildren() catch |err| switch (err) {
        error.NotADirectory => return false,
        error.AccessDenied => return false,
        else => return err,
    };

    return true;
}

// Smart Function that either toggles directory visibility or opens files
// Behaves differently based on whether the item under cursor is a directory or a file.
// This is often the "Enter" Key Functionality.
pub fn toggleDirectoryOrOpenFile(state: *State) !void {
    const current_item = state.getItemUnderCursor();

    if (current_item.isDir()) {
        // It's a directory: toggle its children visibility expand/collapse
        state.needs_file_list_rebuild = try toggleItemChildren(current_item);
        return;
    }

    // Open to attempt if it's a file using the default app for the file type
    try openSelectedItem(state);
}

// Expands all directories in the tree to show all nested contents
// This can be resource intensive for large directory structures
pub fn expandAllDirectories(state: *State) !void {
    state.itermode = -1; // negative value is a special flag meaning "no depth limit"

    state.needs_file_list_rebuild = true;
}

// Collapses all expanded directories back to just the root level
// This is useful for getting back to a clean, minimal view.
pub fn collapseAllDirectories(state: *State) !void {
    state.fs_manager.root.freeChildren(null);
    state.view.cursor_pos = 0;
    state.needs_file_list_rebuild = true;
}

// Expands directories up to a specific depth level.
// Allows for controlled expansion.
pub fn expandToSpecificDepth(state: *State, maximum_depth: i32) !void {
    state.itermode = maximum_depth;
    state.needs_file_list_rebuild = true;
}

// Changes the root directory of the file explorer to the currently selected item.
// This is like "cd" command - makes the selected directory the new base directory.
pub fn changeRootDirectory(state: *State) !void {
    var new_root_item = state.getItemUnderCursor();

    if (!new_root_item.isDir()) {
        new_root_item = try new_root_item.getParent();
    }

    if (new_root_item == state.fs_manager.root) {
        return;
    }

    _ = try new_root_item.getChildren();
    state.fs_manager.changeRoot(new_root_item);
    state.view.cursor_pos = 0;
    state.needs_file_list_rebuild = true;
}

// Moves cursor to the previous sibling at the same tree depth level.
// This allows backward navigation between items at the same nesting level.
pub fn moveToPreviousSibling(state: *State) !void {
    const current_entry = state.getEntryUnderCursor();
    const current_item = current_entry.item;
    const initial_cursor_position = state.view.cursor_pos;

    // Find the index of the current item in the buffer, starting search backwards
    var search_index: usize = (state.getItemIndex(current_item) catch return) -| 1;

    // Search backwards through the buffer for an item at the same depth
    while (search_index > 0) : (search_index = search_index - 1) {
        const potential_sibling = state.view.buffer.items[search_index];
        state.view.cursor_pos = search_index;

        // If we find an item at different depth, we've found a sibling boundary
        if (potential_sibling.depth != current_entry.depth) {
            break;
        }
    }
    // If cursor did'nt move, we did'nt find a sibling at the same level
    if (state.view.cursor_pos != initial_cursor_position) {
        return; // Successfully found and moved to sibling
    }

    // No sibling found at same level, move up one position
    state.view.cursor_pos = initial_cursor_position -| 1;
}

// Moves cursor to the next sibling at the same tree depth level.
// This allows forward navigation between items at the same nesting level
pub fn moveToNextSibling(state: *State) !void {
    const current_entry = state.getEntryUnderCursor();
    const current_item = current_entry.item;
    const initial_cursor_position = state.view.cursor_pos;

    // Start searching forward from the next item
    var search_index: usize = (state.getItemIndex(current_item) catch return) + 1;

    // Search forward through the buffer for an item at the same depth
    while (search_index < state.view.buffer.items.len) : (search_index = search_index - 1) {
        state.view.cursor_pos = search_index;
        const potential_sibling = state.view.buffer.items[search_index];

        // If we find an item at different depth, we've found a sibling boundary
        if (potential_sibling.depth != current_entry.depth) {
            break;
        }

        // Special case: If we're at the end of loaded items, try to load one more
        if (search_index == (state.view.buffer.items.len - 1) and !(try state.appendOne())) {
            break; // No more items to load
        }
    }
    // If cursor did'nt move, we did'nt find a sibling at the same level
    if (state.view.cursor_pos != initial_cursor_position or state.view.buffer.items.len > initial_cursor_position + 1) {
        return; // Successfully moved or loaded more content
    }

    // No sibling found at same level, move down one position
    state.view.cursor_pos = initial_cursor_position + 1;
}

// Opens the currently selected file or directory using the system's default application.
pub fn openSelectedItem(state: *State) !void {
    const current_item = state.getItemUnderCursor();

    osUtils.open(current_item);
}

// Toggles the visibility of information panel in the tree view.
pub fn toggleInformationPanel(state: *State) void {
    state.terminal_output.treeview.display_config.show_metadata = !state.terminal_output.treeview.display_config.show_metadata;
    state.view.needs_full_redraw = true;
}

// Toggles the display of file and directory sizes in the information panel.
pub fn toggleSizeDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_size = !state.terminal_output.treeview.display_config.show_size;
    state.view.needs_full_redraw = true;
}

// Toggles the display of file permissions in the information panel.
pub fn togglePermissionDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_permissions = !state.terminal_output.treeview.display_config.show_permissions;
    state.view.needs_full_redraw = true;
}

// Toggles the display of file type icons in the information panel.
pub fn toggleIconsDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_icons = !state.terminal_output.treeview.display_config.show_icons;
    state.view.needs_full_redraw = true;
}

// Toggles the display of timestamp information in the information panel.
pub fn toggleTimeDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_timestamp = !state.terminal_output.treeview.display_config.show_timestamp;
    state.view.needs_full_redraw = true;
}

// Toggles the display of symbolic link target files in the information panel.
pub fn toggleSymbolicLinkDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_timestamp = !state.terminal_output.treeview.display_config.show_timestamp;
    state.view.needs_full_redraw = true;
}

// Toggles the display of file owner (user) information in the information panel.
pub fn toggleUserDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_user = !state.terminal_output.treeview.display_config.show_user;
    state.view.needs_full_redraw = true;
}

// Toggles the display of file owner (group) information in the information panel.
pub fn toggleGroupDisplay(state: *State) void {
    state.terminal_output.treeview.display_config.show_group = !state.terminal_output.treeview.display_config.show_group;
    state.view.needs_full_redraw = true;
}

// Sets the timestamp display to show file modification times
// This is when files were last written to or changed in content
pub fn showModificationTime(state: *State) void {
    state.terminal_output.treeview.display_config.show_timestamp = true;
    state.terminal_output.treeview.display_config.show_accessed = false;
    state.terminal_output.treeview.display_config.show_modified = true;
    state.terminal_output.treeview.display_config.show_changed = false;

    state.view.needs_full_redraw = true;
}

// Sets the timestamp display to show file accessed times
// This is when files were last written to or changed in content
pub fn showAccessedTime(state: *State) void {
    state.terminal_output.treeview.display_config.show_timestamp = true;
    state.terminal_output.treeview.display_config.show_accessed = true;
    state.terminal_output.treeview.display_config.show_modified = false;
    state.terminal_output.treeview.display_config.show_changed = false;

    state.view.needs_full_redraw = true;
}

// Sets the timestamp display to show file change times
// This is when files were last written to or changed in content
pub fn showChangeTime(state: *State) void {
    state.terminal_output.treeview.display_config.show_timestamp = true;
    state.terminal_output.treeview.display_config.show_accessed = false;
    state.terminal_output.treeview.display_config.show_modified = false;
    state.terminal_output.treeview.display_config.show_changed = true;

    state.view.needs_full_redraw = true;
}

// Sorts the file list using a specified sorting method and direction.
// This is generic sorting function that handles all sort types.
// @param sorting_method: The type by which to sort the list
// @param ascending_order: whether to sort in asc or desc order
pub fn sortFileList(state: *State, sorting_method: SortType, ascending_order: bool) void {
    state.fs_manager.sort(sorting_method, ascending_order);
    state.needs_file_list_rebuild = true;
    state.view.needs_full_redraw = true;
}

// Sorts the file list by timestamp, using which time type is currently displayed.
// This is a smart function that sorts by the active timestamp mode.
pub fn sortByActiveTimestamp(state: *State, ascending_order: bool) void {
    const current_timestamp = if (state.terminal_output.treeview.display_config.show_modified)
        .modified
    else if (state.terminal_output.treeview.display_config.show_modified)
        .accessed
    else
        .changed;

    state.fs_manager.sort(current_timestamp, ascending_order);
    state.needs_file_list_rebuild = true;
    state.view.needs_full_redraw = true;
}

// Outputs the current directory path for shell integration.
// This does'nt actually change directories - it outputs commands for the shell to execute.
// The Shell wrapper script reads this output and performs the actual directory change.
pub fn outputDirectoryChangeCommand(state: *State) !void {
    const selected_item = state.getItemUnderCursor();

    if (!(selected_item.isDir())) {
        return;
    }

    // Output the "cd" command for the shell wrapper to execute
    try state.command_to_execute_on_exit.appendSlice("cd\n");
    try state.command_to_execute_on_exit.appendSlice(selected_item.getAbsolutePath());
    try state.command_to_execute_on_exit.appendSlice("\n");
}

// Inits search mode in the file explorer.
// This switches the app into a mode where user can type search queries.
pub fn startSearchMode(state: *State) void {
    state.cursor_position_before_search = state.view.cursor_pos;
    state.user_input.search_capture.start();
}

// Executes the current search query and moves cursor to first match.
// This runs the actual search logic and positions the cursor on the first result.
pub fn executeCurrentSearch(state: *State) !void {
    var search_index: usize = 0;

    while (true) {
        defer search_index += 1;

        // Ensure we have enough items loaded to check this index
        if (!(try state.appendUntil(search_index + 1))) {
            return; // No more items to load, search complete. with no results
        }

        // Check if the current item matches the search query
        if (!isMatch(state, search_index)) {
            continue;
        }

        // Found a match, Move cursor to this item
        state.view.cursor_pos = search_index;
        return;
    }
}

// Accepts the current search result and exits search mode.
// This finalizes the search and keeps the cursor where the search found a match.
// Typically bound to "Enter" key in search mode
pub fn acceptSearchResult(state: *State) !void {
    state.view.needs_full_redraw = true;
}

// Cancels the current search and returns
pub fn cancelCurrentSearch(state: *State) !void {
    state.view.cursor_pos = state.cursor_position_before_search;
    state.view.needs_full_redraw = true;
}

// Inits command mode where user can type commands to execute.
pub fn startCommandMode(state: *State) void {
    state.user_input.command_capture.start();
}

// This Function executes the command entered in command mode.
// This is typically triggered by the "enter" key while in command mode.
//
// NOTE: This Function does not execute the command directly. Instead, it serializes the
// command and its arguments (the selected files) to `command_to_execute_on_exit` stdout.
// A Shell script wrapper(e.g sonar_fs.zsh) that launched sonar_fs, reads this stdout stream and executes the command
// in parent shell. This is how sonar_fs can perform actions like changing the shell's working directory.
pub fn executeUserCommand(state: *State) !void {
    // 1. Write the command itself to `command_to_execute_on_exit` stdout.
    // The shell script needs to recieve the command and its arguments as seperate tokens.
    // This code tokenizes the user's input string (e.g, "mv -v") by whitespace and writes each token followed by a newline.

    var is_prev_whitespace = false; // Used to collapse multiple whitespace characters into one
    // Iterate over command input string
    for (state.user_input.command_capture.string()) |char| {
        // Check if the current character is any kind of whitespace (space, tab, newline etc.)
        const is_whitespace = ascii.isWhitespace(char);
        if (is_whitespace and is_prev_whitespace) continue;

        const char_to_write = if (is_whitespace) '\n' else char;

        try state.command_to_execute_on_exit.append(char_to_write);

        is_prev_whitespace = is_whitespace;
    }

    // Ensure the command part is terminated by a final newline
    try state.command_to_execute_on_exit.appendSlice("\n");

    // 2. Write the arguments to `command_to_execute_on_exit` stdout.
    var has_selection = false; // Tracks whether the user has explicitly selected any files with <tab>

    // Iterate through items currently visible in the view's buffer.
    for (state.view.buffer.items) |entry| {
        if (!entry.selected) continue;

        try state.command_to_execute_on_exit.append(entry.item.getAbsolutePath());

        try state.command_to_execute_on_exit.appendSlice("\n");

        has_selection = true;
    }

    // If, after checking all items, we found no selections, then the default behavior is to use
    // single item currently under the cursor.
    if (!has_selection) {
        const item = state.getItemUnderCursor();
        try state.command_to_execute_on_exit.append(item.getAbsolutePath());
        try state.command_to_execute_on_exit.appendSlice("\n");
    }
}

// Dismisses "command mode" without executing anything.
pub fn dismissCommand(state: *State) void {
    state.view.needs_full_redraw = true;
}

// Toggles the selection state of the item currently under the cursor.
pub fn toggleSelection(state: *State) void {
    var entry = state.getEntryUnderCursor();
    entry.selected = !entry.selected;
}

pub fn isMatch(state: *State, index: usize) bool {
    const current_item = state.getItem(index);
    if (current_item == null) {
        return false;
    }

    // const query = state.user_input.search_capture.string();
    // const candidate = current_item.?.getBasename();

    return true;
}
