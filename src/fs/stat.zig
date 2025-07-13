const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const linux = std.os.linux;

const owner = @import("./ownerLookup.zig");

const libc = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("grp.h");
    @cInclude("pwd.h");
});

const is_linux = builtin.os.tag == .linux;
const is_intel_mac = builtin.os.tag == .macos and builtin.cpu.arch == .x86_64;

pub const timeType = enum { modified, changed, accessed };

pub const Stat = struct {
    mode: i64,
    size: i64,
    uid: u32,
    gid: u32,
    mtime: isize, // Modified time
    atime: isize, // Accessed time
    ctime: isize, // Last change status

    const Self = @This();

    // Used to retrieve information about a file system object such as a file or directory.
    pub fn stat(absolute_path: []const u8) !Self {
        // The recieved absoluted path is converted to a pointer. This is crucial for zig strings to
        // C functions that accepts null-terminated strings.
        const abs_path_ptr: [*:0]const u8 = @ptrCast(absolute_path);

        // Now, based on the operating system, we choose the correct lstat implementation to use
        if (is_linux) {
            var linux_stat_buffer: linux.Stat = undefined;
            if (linux.lstat(abs_path_ptr, &linux_stat_buffer) != 0) {
                return error.StatError;
            }

            return Self{
                .mode = linux_stat_buffer.mode,
                .size = linux_stat_buffer.size,
                .uid = linux_stat_buffer.uid,
                .gid = linux_stat_buffer.gid,
                .mtime = linux_stat_buffer.mtime(),
                .atime = linux_stat_buffer.atime(),
                .ctime = linux_stat_buffer.ctime(),
            };
        } else if (is_intel_mac) {
            var intel_stat_buffer: std.c.Stat = undefined;
            if (std.c.stat(abs_path_ptr, &intel_stat_buffer) != 0) {
                return error.StatError;
            }

            return Self{
                .mode = intel_stat_buffer.mode,
                .size = intel_stat_buffer.size,
                .uid = intel_stat_buffer.uid,
                .gid = intel_stat_buffer.gid,
                .mtime = intel_stat_buffer.mtime(),
                .atime = intel_stat_buffer.atime(),
                .ctime = intel_stat_buffer.ctime(),
            };
        } else {
            var other_stat_buffer: libc.struct_stat = undefined;
            if (libc.lStat(abs_path_ptr, &other_stat_buffer) != 0) {
                return error.StatError;
            }

            return Self{
                .mode = other_stat_buffer.st_mode,
                .size = other_stat_buffer.st_size,
                .uid = other_stat_buffer.st_uid,
                .gid = other_stat_buffer.st_gid,
                .mtime = other_stat_buffer.st_mtimespec.tv_sec,
                .atime = other_stat_buffer.st_atimespec.tv_nsec,
                .ctime = other_stat_buffer.st_ctimespec.tv_nsec,
            };
        }
    }

    // FILE TYPES

    pub fn isExecutable(self: *Self) bool {
        return self.hasUserExecutePermission();
    }

    pub fn isRegularFile(self: *Self) bool {
        return libc.S_ISREG(self.mode);
    }

    pub fn isDir(self: *Self) bool {
        return libc.S_ISDIR(self.mode);
    }

    pub fn isLinkFile(self: *Self) bool {
        return libc.S_ISLNK(self.mode);
    }

    pub fn isBlockFile(self: *Self) bool {
        return libc.S_ISBLK(self.mode);
    }

    pub fn isFifoFile(self: *Self) bool {
        return libc.S_IFIFO(self.mode);
    }

    pub fn isCharSpecialFile(self: *Self) bool {
        return libc.S_ISCHR(self.mode);
    }

    pub fn isSocketFile(self: *Self) bool {
        return libc.S_ISSOCK(self.mode);
    }

    // USER PERMISSIONS

    // Check whether the user who owns the file has execute permissions on the file.
    //
    // STEPS TO CHECK PERMISSION
    // 1. Depending on the os, get the execute permission mask for the user who owns the file. This mask can be used to
    // check if the user has execute permission on the file.
    // 2. Perform a bitwise AND operation on the mask and the file's mode. This operation checks the execute
    // permission bit is set in the file's mode.
    pub fn hasUserExecutePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IXUSR else libc.S_IXUSR;
        return (mask & self.mode) > 0;
    }

    // Check whether the user who owns the file has write permissions on the file.
    pub fn hasUserWritePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IWUSR else libc.S_IWUSR;
        return (mask & self.mode) > 0;
    }

    // Check whether the user who owns the file has read permissions on the file.
    pub fn hasUserReadPermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IRUSR else libc.S_IRUSR;
        return (mask & self.mode) > 0;
    }

    // GROUP PERMISSIONS

    pub fn hasGroupExecutePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IXGRP else libc.S_IXGRP;
        return (mask & self.mode) > 0;
    }

    pub fn hasGroupWritePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IWGRP else libc.S_IWGRP;
        return (mask & self.mode) > 0;
    }

    pub fn hasGroupReadPermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IRGRP else libc.S_IRGRP;
        return (mask & self.mode) > 0;
    }

    // OTHER PERMISSIONS

    // Checks whether other (users who are not owner or part of the owning group)
    // have execute permissions on the file
    pub fn hasOtherExecutePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IXOTH else libc.S_IXOTH;
        return (mask & self.mode) > 0;
    }

    pub fn hasOtherWritePermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IWOTH else libc.S_IWOTH;
        return (mask & self.mode) > 0;
    }

    pub fn hasOtherReadPermission(self: *Self) bool {
        const mask = if (is_linux) linux.S.IROTH else libc.S_IROTH;
        return (mask & self.mode) > 0;
    }

    // Get Group and User names from gid and uid
    pub fn getUsername(self: *Self, map: owner.UserMap) ![]u8 {
        return try owner.getIdName(self.uid, map, .user);
    }

    pub fn getGroupname(self: *Self, map: owner.UserMap) ![]u8 {
        return try owner.getIdName(self.gid, map, .group);
    }
};
