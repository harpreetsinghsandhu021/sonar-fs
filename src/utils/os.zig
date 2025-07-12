const std = @import("std");
const builtin = @import("builtin");
const process = std.process;

// Takes a file path and attempts to open it using the default application for
// the current operating system.
pub fn open(path: []const u8) !void {
    switch (builtin.os.tag) {
        .macos => try openMacOs(path),
        .linux => try openLinux(path),
        else => return,
    }
}

// Takes a file path and attempts to open it using `open` command on macos.
fn openMacOs(path: []const u8) !void {
    var argv = [_][]const u8{ "open", path };
    try run(&argv);
}

// Takes a file path and attempts to open it using `xdg-open` command on linux.
fn openLinux(path: []const u8) !void {
    var argv = [_][]const u8{ "xdg-open", path };
    try run(&argv);
}

// Takes an array of string representing a command and its arguments, and attempts to execute the
// command using the `process` module.
pub fn run(argv: [][]const u8) !void {
    // Create an arena allocator to manage memory for the child process.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Init a child process using `process.Child`, passing the command and its arguments along with allocator.
    var child = process.Child.init(argv, allocator);
    // Set the behavior for the child process's standard output and standard error streams to close them, which
    // prevents the child process from inheriting the parent process's file descriptors.
    child.stdout_behavior = .Close;
    child.stderr_behavior = .Close;

    // Attempt to spawn the child process and wait for it to complete.
    _ = child.spawnAndWait();
}
