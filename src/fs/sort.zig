const std = @import("std");
const FileDir = @import("fileDir.zig").FileDir;

pub const SortType = enum { size, name, modified, changed, accessed };

const Context = struct {
    sortBy: SortType,
    asc: bool,
};

fn getTime(entry: *FileDir, how: SortType) isize {
    if (how == .accessed) {
        const s = entry.getStat() catch return 0;
        return s.atime;
    }

    if (how == .modified) {
        const s = entry.getStat() catch return 0;
        return s.mtime;
    }

    if (how == .changed) {
        const s = entry.getStat() catch return 0;
        return s.ctime;
    }
}

// Defines a comparator function that is used `std.mem.sort` to determine the order of Entries.
const Comparator = struct {
    pub fn lessThanFunction(context: Context, lhs: *FileDir, rhs: *FileDir) bool {
        switch (context.sortBy) {
            .size => return sortBySize(context, lhs, rhs),
            .name => return sortByName(context, lhs, rhs),
            .modified => return sortByTime(context, lhs, rhs),
            .changed => return sortByTime(context, lhs, rhs),
            .accessed => return sortByTime(context, lhs, rhs),
        }
    }

    fn sortBySize(context: Context, lhs: *FileDir, rhs: *FileDir) bool {
        const a = lhs.stat.?.size;
        const b = rhs.stat.?.size;

        if (context.asc) {
            return a < b;
        }

        return a > b;
    }

    // Comparison function used to sort entries based on their name.
    fn sortByName(context: Context, lhs: *FileDir, rhs: *FileDir) bool {
        const a = lhs.getBasename();
        const b = rhs.getBasename();

        const len = if (a.len < b.len) a.len else b.len;

        for (0..len) |i| {
            const chara = a[i];
            const charb = b[i];

            if (chara == charb) continue;

            if (context.asc) {
                return chara < charb;
            }

            return chara > charb;
        }

        if (context.asc) {
            return a.len < b.len;
        }

        return a.len > b.len;
    }

    fn sortByTime(context: Context, lhs: *FileDir, rhs: *FileDir) bool {
        const a = getTime(lhs, context.sortBy);
        const b = getTime(rhs, context.sortBy);

        if (context.asc) {
            return a < b;
        }

        return a > b;
    }
};

pub fn sort(items: std.ArrayList(*FileDir), sortBy: SortType, asc: bool) void {
    const context = Context{ .sortBy = sortBy, .asc = asc };
    std.mem.sort(*FileDir, items.items, context, Comparator.lessThanFunction);
}
