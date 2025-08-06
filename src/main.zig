//! This File serves as the main entry point for the `sonar_fs` executable.
//!
//! Its primary responsibilities are:
//! 1. Initializing Global memory allocator
//! 2. Parsing command-line arguments and enviroment variables to construct application's config.
//! 3. Inits the main App struct.
//! 4. Executing the application's main loop via `app.run`.
//! 5. Ensure all resources are deinitialized gracefully upon exit.
//!
const std = @import("std");

const App = @import("./app/index.zig");
const args = @import("./context/args.zig");

pub fn main() !void {
    var config = App.Config{ .root = "." };
    try args.loadEnviromentConfig(&config);

    if (try args.loadCommandLineConfig(&config)) {
        return;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = try App.init(allocator, &config);
    defer app.deinit();
    try app.run();
}
