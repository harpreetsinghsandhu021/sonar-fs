const std = @import("std");
const Allocator = std.mem.Allocator;
const SortType = @import("sort.zig").SortType;
const FileDir = @import("fileDir.zig").FileDir;
const Iterator = @import("fsIterator.zig").Iterator;

const testing = std.testing;

// Manages all filesystem related operations including maintaining file system hierarchy working with individual files and
// directories, and providing an iterator for traversing the file system.
pub const Manager = struct {
    allocator: Allocator,
    root: *FileDir,

    const Self = @This();

    pub fn init(allocator: Allocator, root: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .root = try FileDir.init(allocator, root),
        };
    }

    pub fn deinit(self: *Self) void {
        self.root.deinit();
    }

    pub fn findParent(self: *Self, child: *FileDir) !?*FileDir {
        return _findParent(self.root, child);
    }

    // This function moves up one directory level.
    //
    // APPROACH:
    // Tries to get the parent of the current root. If no parent found, returns null.
    // Checks if the current root is a child of the new root to prevent memory leaks.
    // If not found as child, deallocates the old root and returns the new root.
    pub fn up(self: *Self) !?*FileDir {
        var new_root = self.root.getParent() catch |err| {
            if (err == error.NoParentFound) {
                return null;
            } else {
                return err;
            }
        };

        // Checks if the current root is the child of the new root.
        // If it's not found as a child (which could happen if the file system structure was modified externally or there's an inconsistency),
        // we deallocate it to prevent memory leak.
        const index = try new_root.getChildIndex(self.root);
        if (index == null) {
            self.root.deinit();
        }

        self.root = new_root;
        return self.root;
    }

    // This function moves down to a specific child directory.
    //
    // APPROACH:
    // Uses _findParent to verify the child exists in the tree. If the child is'nt found, returns null.
    // Checks if the parent is the current root, deallocates parent's other children except the target child.
    // If parent is'nt the root, deallocates the old root. Sets and returns the new root.
    pub fn down(self: *Self, child: *FileDir) !?*FileDir {
        const _parent = try _findParent(self.root, child);
        if (_parent == null) return null;

        var parent = _parent.?;
        const root = self.root == parent;
        parent.deinitandSkipChildren(child);

        if (!root) {
            self.root.deinit();
        }

        self.root = child;
        return self.root;
    }

    // This function changes the root to a new item directly, but with crucial memory management step.
    pub fn changeRoot(self: *Self, newRoot: *FileDir) void {
        self.root.deinitandSkipChildren(newRoot);
        self.root = newRoot;
    }

    // A Recursive function that looks for the parent of a given child item in a tree structure.
    //
    // DFS APPROACH:
    // First check if the parent has any children, if not, return null.
    // If there are children, iterate through each child in the children list. For each child:
    // If the current child is the target child, returns the current parent.
    // If not found, recursively call _findParent on each child to search deeper in the tree.
    fn _findParent(parent: *FileDir, ch: *FileDir) !?*FileDir {
        if (!parent.hasChildren()) {
            return null;
        }

        const children = try parent.getChildren();

        for (children.items) |child| {
            if (child == ch) {
                return parent;
            }

            if (try _findParent(child, ch)) |par| {
                return par;
            }
        }

        return null;
    }

    pub fn sort(self: *Self, sortBy: SortType, asc: bool) void {
        self.root.sortChildren(sortBy, asc);
    }

    pub fn iterator(self: *Self, depth: i32) !Iterator {
        return Iterator.init(self.allocator, self.root, depth);
    }
};
