//! APPLICATION STATE MANAGER
//!
//! This is a comprehensive State Manager for the Application. This structure holds all the state needed
//! to run the file explorer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Viewport = @import("../view/viewport.zig").Viewport;
const ViewManager = @import("../view/viewManager.zig").ViewManager;
const Output = @import("../app/display/output.zig");
const Input = @import("../app/display/input.zig").InputHandler;
const AppAction = @import("../app/display/input.zig").AppAction;
const Manager = @import("../fs/fsManager.zig").Manager;
const Config = @import("../app/index.zig").Config;
const Iterator = @import("../fs/fsIterator.zig").Iterator;
const Entry = @import("../fs/fsIterator.zig").Entry;
const Item = @import("../fs/fileDir.zig").FileDir;
const actions = @import("../app/display/actions.zig");

display_viewport: *Viewport,
view: *ViewManager,
terminal_output: *Output,
user_input: *Input,
fs_manager: *Manager,

// Command Execution System
// This is a clever mechanism that allows the file explorer to execute commands in the user's SHELL after the explorer exists.
// For example, you could navigate to a directory in the explorer, press a key, and have it automatically "cd" to the directory
// in the actual shell when you exit.
command_to_execute_on_exit: *std.ArrayList(u8),

needs_file_list_rebuild: bool,
itermode: i32,
iterator: ?*Iterator,
cursor_position_before_search: usize, // Remember where the cursor was before searching, to go back
// fuzzy_search: bool, // Should "txt" match "test.txt" (fuzzy matching)
// ignore_case: bool, // Should "README" match "readme"
use_fullscreen: bool,
allocator: Allocator,

const Self = @This();

pub fn init(allocator: Allocator, config: *Config) !Self {
    const viewport = try allocator.create(Viewport);
    viewport.* = try Viewport.init();

    const view = try allocator.create(ViewManager);
    view.* = ViewManager.init(allocator);

    const output = try allocator.create(Output);
    output.* = try Output.init(allocator, config);

    const input = try allocator.create(Input);
    input.* = try Input.init(allocator);

    const manager = try allocator.create(Manager);
    manager.* = try Manager.init(allocator, config.root);

    const charArray = std.ArrayList(u8);

    const stdout = try allocator.create(charArray);
    stdout.* = charArray.init(allocator);

    return Self{
        .display_viewport = viewport,
        .view = view,
        .terminal_output = output,
        .user_input = input,
        .fs_manager = manager,
        .command_to_execute_on_exit = stdout,
        .needs_file_list_rebuild = false,
        .itermode = -2,
        .iterator = null,
        .cursor_position_before_search = 0,
        .use_fullscreen = config.use_fullscreen,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.display_viewport.deinit();
    self.allocator.destroy(self.display_viewport);

    self.view.deinit();
    self.allocator.destroy(self.view);

    self.terminal_output.deinit();
    self.allocator.destroy(self.terminal_output);

    self.user_input.deinit();
    self.allocator.destroy(self.user_input);

    self.command_to_execute_on_exit.deinit();
    self.allocator.destroy(self.command_to_execute_on_exit);

    if (self.iterator) |iter| {
        iter.deinit();
        self.allocator.destroy(iter);
    }

    self.fs_manager.deinit();
    self.allocator.destroy(self.fs_manager);
}

// ========================================================================
// SETUP BEFORE RUNNING - Preparing the stage for our application
// ========================================================================
//
// This Function prepares the terminal enviroment and initializes any dynamic state.
pub fn preRun(self: *Self) !void {

    // FULLSCREEN MODE SETUP
    // If we're using fullscreen mode, we must switch to an alternate buffer.
    // This means we draw everything to seperate screen layer, keeping the user's terminal clean.
    // It feels seamless to the user.
    if (self.use_fullscreen) {
        self.terminal_output.writer.disableBuffering(); // Disable line buffering
        try self.terminal_output.display.enableAlternateBuffer(); // Switch to alternate buffer
        try self.terminal_output.display.clearScreen(); // Clear everything to start fresh
    }

    // INIT VIEW BOUNDS
    try self.display_viewport.initBounds();

    // LOAD ROOT DIRECTORY CHILDREN
    // This ensures the file manager is ready to display the initial directory listing
    _ = try self.fs_manager.root.getChildren();

    // FLAG THAT FILE LIST NEEDS TO BE REBUILT
    self.needs_file_list_rebuild = true;
}

// ========================================================================
// CLEANUP AFTER RUNNING - Tearing down the stage for our application
// ========================================================================
//
// This Function restores the terminal to its original state and hanlde any final tasks.
pub fn postRun(self: *Self) !void {
    // EXIT FULLSCREEN MODE
    // If we used an alternate buffer, we must switch back to main buffer
    if (self.use_fullscreen) {
        try self.terminal_output.display.disableAlternateBuffer();
    }

    // EXECUTE EXIT COMMAND
    if (self.command_to_execute_on_exit.items.len > 0) {
        try self.writeShellCommandToStdout();
    }
}

// This Function handles when the user resizes their terminal window.
// We need to recalculate our display boundaries and potentially redraw everything.
pub fn updateViewport(self: *Self) !void {
    const terminal_size_changed = try self.display_viewport.updateBounds();

    // If terminal size has changed, we need to redraw everything from scratch because our
    // layout calculations are now invalid
    self.view.needs_full_redraw = terminal_size_changed or self.view.needs_full_redraw;
}

// This Function walks through the file system and build the list of files/directories that will be
// shown to the user.
pub fn fillBuffer(self: *Self) !void {
    if (!self.needs_file_list_rebuild) {
        return;
    }

    defer self.needs_file_list_rebuild = false;

    // Init the directory walker
    try self.initializeIterator();

    // Calculate how many items we need
    // We only need to load enough items to load the visible area of the screen
    const items_needed_for_display = self.view.viewport_start + self.display_viewport.visible_rows;

    // Clear the old file list - Start fresh
    self.view.buffer.clearAndFree();

    // Walk through files and build the display list
    while (self.iterator.?.next()) |file_entry| {
        try self.view.buffer.append(file_entry);

        // No point loading more files that we can display
        if (self.view.buffer.items.len >= items_needed_for_display) {
            break;
        }
    }

    // Reset
    self.needs_file_list_rebuild = true;
    self.itermode = 2;
}

// This Functions sets up the iterator that walks through files and directories.
// It handles cleanup of any existing iterator and creates a fresh one.
fn initializeIterator(self: *Self) !void {
    if (self.iterator) |old_iterator| {
        old_iterator.deinit();
        self.allocator.destroy(old_iterator);
    }

    const iterator = try self.allocator.create(Iterator);
    iterator.* = try self.fs_manager.iterator(self.itermode);

    self.iterator = iterator;
}

// This Function ensures our view component knows about the current state of the file iterator
// and can make smart decisions about what to display.
pub fn updateView(self: *Self) !void {
    try self.view.update(self.iterator.?, self.display_viewport.visible_rows);
}

// ========================================================================
// MAIN RENDERING PIPELINE - Drawing the complete interface
// ========================================================================
//
// This is the main function that orchestrates drawing everything the user sees.
// It handles file listing, search highlighting, and input capture displays.
pub fn printContents(self: *Self) !void {
    // Draw the main file list
    // This is the core rendering call that draws all the files and directories
    try self.terminal_output.printContents(self.display_viewport.viewport_start, self.view, self.user_input.command_capture.is_capturing);

    // Draw input capture overlays
    if (self.user_input.search_capture.is_capturing) {
        // Draw the input box at the bottom of the screen as an overlay on top of the list
        try self.terminal_output.printCaptureString(self.view, self.display_viewport, self.user_input.search_capture);
    } else if (self.user_input.command_capture.is_capturing) {
        try self.terminal_output.printCaptureString(self.view, self.display_viewport, self.user_input.command_capture);
    }
}

// ========================================================================
// ACTION EXECUTER - The Command Dispatcher
// ========================================================================
//
// This is like a huge switch statement that takes user actions and executes the appropriate response.
// It's the central hub that connect's user intent with the application behavior.
pub fn executeAction(self: *Self, user_action: AppAction) !void {
    // Cursor Position Tracking
    // Remember where the cursor was before this action.
    self.view.previous_cursor = self.view.cursor_pos;

    switch (user_action) {
        .up => actions.moveCursorUp(self),
        .down => actions.moveCursorDown(self),
        .top => actions.gotoTop(self),
        .bottom => actions.gotoBottom(self),
        .left => try actions.navigateToParentItem(self),
        .right => try actions.navigateToChildItem(self),
        .enter => try actions.toggleDirectoryOrOpenFile(self),
        .expand_all => try actions.expandAllDirectories(self),
        .collapse_all => try actions.collapseAllDirectories(self),
        .prev_fold => try actions.moveToPreviousSibling(self),
        .next_fold => try actions.moveToNextSibling(self),
        .change_root => try actions.changeRootDirectory(self),
        .open_item => try actions.openSelectedItem(self),
        .change_dir => try actions.outputDirectoryChangeCommand(self),
        .depth_one => try actions.expandToSpecificDepth(self, 0),
        .depth_two => try actions.expandToSpecificDepth(self, 1),
        .depth_three => try actions.expandToSpecificDepth(self, 2),
        .depth_four => try actions.expandToSpecificDepth(self, 3),
        .depth_five => try actions.expandToSpecificDepth(self, 4),
        .depth_six => try actions.expandToSpecificDepth(self, 5),
        .depth_seven => try actions.expandToSpecificDepth(self, 6),
        .depth_eight => try actions.expandToSpecificDepth(self, 7),
        .depth_nine => try actions.expandToSpecificDepth(self, 8),
        .toggle_info => actions.toggleInformationPanel(self),
        .toggle_group => actions.toggleGroupDisplay(self),
        .toggle_icons => actions.toggleIconsDisplay(self),
        .toggle_link => actions.toggleSymbolicLinkDisplay(self),
        .toggle_perm => actions.togglePermissionDisplay(self),
        .toggle_size => actions.toggleSizeDisplay(self),
        .toggle_time => actions.toggleTimeDisplay(self),
        .toggle_user => actions.toggleUserDisplay(self),
        .time_accessed => actions.showAccessedTime(self),
        .time_changed => actions.showChangeTime(self),
        .time_modified => actions.showModificationTime(self),
        .sort_name => actions.sortFileList(self, .name, true),
        .sort_size => actions.sortFileList(self, .size, true),
        .sort_time => actions.sortByActiveTimestamp(self, true),
        .sort_name_descending => actions.sortFileList(self, .name, false),
        .sort_size_descending => actions.sortFileList(self, .size, false),
        .sort_time_descending => actions.sortByActiveTimestamp(self, false),
        .accept_search => actions.acceptSearchResult(self),
        .dismiss_search => actions.dismissSearch(self),
        .update_search => actions.executeCurrentSearch(self),
        .start_command_mode => actions.startCommandMode(self),
        .exec_command => actions.executeUserCommand(self),
        .dismiss_command => actions.dismissCommand(self),
        .select => actions.toggleSelection(self),
        .quit => unreachable,
        .no_action => unreachable,
    }
}

pub fn getAppAction(self: *Self) !AppAction {
    return try self.user_input.getNextAction();
}

// This Function finds the index of a specific file.
pub fn getItemIndex(self: *Self, target_file_item: *Item) !usize {
    // Search through our entire display buffer
    // We have to check every entry because items are'nt sorted by memory address
    for (0..self.view.buffer.items.len) |buffer_index| {
        if (self.view.buffer.items[buffer_index].item != target_file_item) {
            continue;
        }

        return buffer_index;
    }

    return error.NotFound;
}

// This Function attempts to retrieve the next entry from iterator and append it to the view buffer.
pub fn appendOne(self: *Self) !bool {
    if (self.iterator == null) {
        return false;
    }

    const entry = try self.iterator.?.next();
    if (entry == null) {
        return false;
    }

    try self.view.buffer.append(entry);

    return true;
}

// This Function attempts the append the next entry to the view buffer upto the specified index.
pub fn appendUntil(self: *Self, new_len: usize) !bool {
    while (true) {
        if (self.view.buffer.items.len >= new_len) {
            break;
        }

        if (!(try self.appendOne())) {
            return false;
        }
    }

    return self.view.buffer.items.len >= new_len;
}

// This Function gets the actual file/directory that the cursor is pointing to.
pub fn getItemUnderCursor(self: *Self) *Item {
    return self.getEntryUnderCursor().item;
}

// This Function gets the file entry that the cursor is currently pointing to.
// This assumes the cursor is always at a valid position.
pub fn getEntryUnderCursor(self: *Self) *Entry {
    return self.view.buffer.items[self.view.cursor_pos];
}

// This Function gets the file entry at the given index.
pub fn getEntry(self: *Self, index: usize) ?*Entry {
    if (index >= self.view.buffer.items.len) {
        return null;
    }

    return self.view.buffer.items[index];
}

// This Functions gets the actual file/directory at the given index.
pub fn getItem(self: *Self, index: usize) ?*Item {
    if (self.getEntry(index)) |entry| {
        return entry.item;
    }

    return null;
}

// Writes the command stored in `self.command_to_execute_on_exit` to the process's standard output.
// This is a mechanism by which sonar_fs communicates a command back to the calling shell (e.g to change
// the directory with cd).
//
// Before writing to command_to_execute_on_exit, if sonar_fs is not in fullscreen mode, it will clear the
// TUI elements from the screen to leave a clean prompt for the shell. In fullscreen mode, the alternate
// screen buffer is simply discarded, so no manual clearing is needed.
pub fn writeShellCommandToStdout(self: *Self) !void {
    if (!self.use_fullscreen) {
        self.terminal_output.writer.disableBuffering();
        try self.terminal_output.display.clearLinesBelow(self.display_viewport.viewport_start);
    }

    _ = try std.io.getStdOut().writer().write(self.command_to_execute_on_exit.items);
}
