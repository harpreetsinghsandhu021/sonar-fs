const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const Stat = @import("stat.zig");
const sort = @import("sort.zig");

// The Basic component of the tree. Can be either a file or a directory. By default, init to directory.
pub const FileDir = struct {
    allocator: Allocator,
    path_buffer: [std.fs.max_path_bytes]u8,
    path_len: usize,
    stat: ?Stat.Stat,
    parent: ?*Self,
    children: ?std.ArrayList(*Self),

    const Self = @This();

    pub fn init(allocator: Allocator, root: []const u8) !*Self {
        var dir = fs.cwd();

        if (root.len > 1 or root[0] != '.') {
            dir = try dir.openDir(root, .{});
        }

        var fileDir = try allocator.create(Self);

        const path_buff = try dir.realpath(".", &fileDir.path_buffer);

        fileDir.allocator = allocator;
        fileDir.path_len = path_buff.len;
        fileDir.stat = null;
        fileDir.parent = null;
        fileDir.children = null;

        return fileDir;
    }

    pub fn deinit(self: *Self) void {
        self.freeChildren(null);
        self.allocator.destroy(self);
    }

    // Returns Absolute path of the FileDir
    pub fn getAbsolutePath(self: *Self) []const u8 {
        const abs_path = self.path_buffer[0..self.path_len];
        return abs_path;
    }

    // Returns basename of the FileDir
    pub fn getBasename(self: *Self) []const u8 {
        const abs_path = self.path_buffer[0..self.path_len];
        return fs.path.basename(abs_path);
    }

    // Returns path to the directory
    pub fn getDirectoryPathname(self: *Self) ?[]const u8 {
        return fs.path.dirname(self.getAbsolutePath());
    }

    pub fn getStat(self: *Self) !Stat.Stat {
        if (self.stat) |s| {
            return s;
        }

        self.stat = try Stat.Stat.stat(self.getAbsolutePath());
        return self.stat.?;
    }

    pub fn isExecutable(self: *Self) bool {
        return self.stat.?.isExecutable();
    }

    pub fn isDir(self: *Self) bool {
        return self.stat.?.isDir();
    }

    pub fn isLink(self: *Self) bool {
        return self.stat.?.isLinkFile();
    }

    pub fn mode(self: *Self) !u16 {
        return self.stat.?.mode;
    }

    pub fn size(self: *Self) !i64 {
        return self.stat.?.size;
    }

    // Retrieves the parent directory of the current item.
    //
    // The purpose of this method is to provide a way to navigate up the directory hierarchy from a given item.
    pub fn getParent(self: *Self) !*Self {
        if (self.parent) |parent| {
            return parent;
        }

        if (self.getDirectoryPathname()) |parent_path| {
            self.parent = Self.init(self.allocator, parent_path);
            try self.setChildren();
            return self.parent.?;
        }

        return error.NoParentFound;
    }

    // Updates the parent's children list to include the current item.
    //
    // When a new item is created, it needs to be added to the parent's children list. This method is called by getParent()
    // method to update the parent's children after the parent has been initialized.
    pub fn setChildren(self: *Self) void {
        if (self.parent == null) return;

        var parent = self.parent.?;
        var children = try parent.getChildren();

        for (0..children.items.len) |i| {
            const child = children.items[i];

            // Check if current item's absolute path matches existing child's absolute path. This prevents duplicate children in the
            // parent's children list which could lead to incorrect behavior and potential memory leaks.
            if (self.getAbsolutePath() == child.getAbsolutePath() and std.mem.eql(u8, &self.path_buffer, &child.path_buffer)) {
                // Replace existing child with current item and destroy old child.
                children.items[i] = self;
                self.allocator.destroy(child);
                return;
            }
        }
    }

    // Retrieves the children of a directory item. By retrieving the children list, we can access the properties and attributes of each child.
    pub fn getChildren(self: *Self) !std.ArrayList(*Self) {
        if (!self.isDir()) {
            return error.NotADirectory;
        }

        if (self.children) |child| {
            return child;
        }

        const absolute_path = self.getAbsolutePath();
        const dir = try fs.openDirAbsolute(absolute_path, .{ .iterate = true });
        var iterator = dir.iterateAssumeFirstIteration();

        var List = std.ArrayList(*Self).init(self.allocator);

        const isRootUnix = self.path_len == 1 and self.path_buffer[0] == '/';
        const isRootWindows = self.path_len == 3 and self.path_buffer[1] == ':' and self.path_buffer[2] == '\\';

        while (true) {
            const entry = iterator.next() catch break;

            if (entry == null) {
                break;
            }

            var item = try self.allocator.create(Self);
            var len: usize = 0;

            @memcpy(item.path_buffer[0..absolute_path.len], absolute_path);
            if (isRootUnix or isRootWindows) {
                len = absolute_path.len + entry.?.name.len;
                @memcpy(item.path_buffer[(absolute_path.len)..len], entry.?.name);
            } else {
                item.path_buffer[absolute_path.len] = fs.path.sep;
                len = absolute_path.len + 1 + entry.?.name.len;
                @memcpy(item.path_buffer[(absolute_path.len + 1)..len], entry.?.name);
            }

            item.path_buffer[len] = 0;
            item.path_len = len;
            item.stat = null;
            item.parent = self;
            item.children = null;
            item.allocator = self.allocator;

            try List.append(item);
        }

        self.children = List;
        return List;
    }

    pub fn getChildIndex(self: *Self, child: *Self) !?usize {
        if (self.children == null) return null;

        return std.mem.indexOf(*Self, self.children.?.items, child);
    }

    // Recursively frees all the children of an item, expect for a specified child.
    pub fn freeChildren(self: *Self, childToSkip: ?*Self) void {
        if (self.children == null) return;

        for (self.children.?.items) |item| {
            if (childToSkip != null and childToSkip == item) {
                childToSkip.?.parent = null;
                continue;
            }

            var fileDir = item;
            fileDir.freeChildren(childToSkip);
            self.allocator.destroy(fileDir);
        }
        self.children.?.deinit();
        self.children = null;
    }

    // This function is used in scenarios where a `FileDir` object needs to be removed from the file system hierarchy but one of
    // them needs to be preserved and reused.
    //
    // By skipping the child object during deinit, the function ensures the child pointer remains valid and can be used somewhere
    // else in the program.
    pub fn deinitandSkipChildren(self: *Self, child: *Self) void {
        self.freeChildren(child);
        self.allocator.destroy(self);
    }

    // Sorts the children of the current item based on the specified sorting critieria.
    //
    // This function recursively sorts the children of current item, as well as their own children, to ensure the entire subtree is
    // sorted consistently.
    pub fn sortChildren(self: *Self, sortBy: sort.SortType, asc: bool) void {
        if (self.children) |entries| {
            var entries_arr = entries;
            sort.sort(&entries_arr, sortBy, asc);
            for (entries.items) |entry| entry.sortChildren(sortBy, asc);
        }
    }

    pub fn hasChildren(self: *Self) bool {
        return self.children != null;
    }

    pub fn hasParent(self: *Self) bool {
        return self.parent != null;
    }
};
