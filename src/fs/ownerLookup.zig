const std = @import("std");

const libc = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("grp.h");
    @cInclude("pwd.h");
});

// Represents an owner(user/group)
//
// By storing the name of the user/group in a fixed size buffer, we avoid the risk of dynamic
// memory allocation which could prove error-prone and inefficient in some cases.
pub const Owner = struct {
    buffer: [256]u8, // Stores the name of the user/group
    len: usize, // Stores the length of the name

    pub fn name(self: *Owner) []u8 {
        return self.buffer[0..self.len];
    }
};

// Stores the names of Owner(user/group) that supports efficient lookup by ID.
pub const UserMap = std.AutoHashMap(u32, *Owner);

pub fn deinitUserMap(map: *UserMap) void {
    // By deinitializing the map first, we ensure that it's in a consistent state
    defer map.deinit();

    const iterator = map.iterator();
    while (iterator.next()) |item| {
        map.allocator.destroy(item.value_ptr.*); // AutoHashMap stores values as pointers, so we free pointers not the value itself
    }
}

const IDType = enum {
    user,
    group,
};

// This functions first checks if an owner with the given id exists, if not creates it and return.
pub fn getIdName(id: u32, map: *UserMap, idType: IDType) ![]u8 {
    if (map.get(id)) |user| {
        return user.name();
    }

    const owner = try map.allocator.create(Owner);

    switch (idType) {
        .group => setIdName(libc.getgrgid(id).*.gr_name, owner),
        .user => setIdName(libc.getpwuid(id).*.pw_name, owner),
    }

    return owner.name();
}

// Helper function used to set the name of an owner based on the C style string.
pub fn setIdName(c_str: [*c]u8, owner: *Owner) void {
    owner.len = 0;

    for (0..owner.buffer.len) |i| {
        owner.len = i;
        const char = c_str[i];
        if (char == 0) break;
        owner.buffer[i] = char;
    }
}
