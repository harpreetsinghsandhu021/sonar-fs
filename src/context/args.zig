const std = @import("std");
const Config = @import("../app/index.zig").Config;
const Stat = @import("../fs/stat.zig").Stat;

// Version constant for the application
const APPLICATION_VERSION = "0.1.1";

// Source of configuration settings
const ConfigSource = enum { from_enviroment, from_command_line };

// Reads and applies configuration from enviroment variables
pub fn loadEnviromentConfig(app_config: *Config) !void {
    const ENV_CONFIG_KEY = "SONAR_DEFAULT_COMMAND";

    const env_config_value = std.posix.getenv(ENV_CONFIG_KEY);
    if (env_config_value == null) {
        return;
    }

    // Split the enviroment value into arguments
    const ArgumentSplitter = std.mem.SplitIterator(u8, .sequence);
    const env_args_iterator = std.mem.splitSequence(u8, env_config_value.?, " ");

    // Process the arguments
    _ = try ConfigurationParser(ArgumentSplitter).parseAndApply(
        app_config,
        env_args_iterator,
        ConfigSource.from_enviroment,
    );
}

// Processes command-line arguments to configure the application
pub fn loadCommandLineConfig(app_config: *Config) !bool {
    // Get command line arguments iterator
    var arg_iterator = std.process.args();

    // Skip the program name (first argument)
    if (!arg_iterator.skip()) {
        return false;
    }

    // Process remaining arguments
    return try ConfigurationParser(std.process.ArgIterator).parseAndApply(
        app_config,
        arg_iterator,
        ConfigSource.from_command_line,
    );
}

// Generic configuration parser that works with different iterator types
fn ConfigurationParser(IteratorType: type) type {
    return struct {
        // Parses Configuration options from an iterator
        pub fn parseAndApply(app_config: *Config, iterator: IteratorType, source: ConfigSource) !bool {
            var arg_position: usize = 0;
            var arg_iterator = iterator;

            while (arg_iterator.next()) |current_arg| {
                defer arg_position += 1;

                // Handle directory path argument (only from command line)
                if (isDirectoryArgument(current_arg, source)) {
                    app_config.root = current_arg;
                    continue;
                }

                // Process Configuration flags
                try processConfigurationFlag(
                    app_config,
                    current_arg,
                );
            }

            return false;
        }

        // Process individual configuration flags
        fn processConfigurationFlag(app_config: *Config, current_flag: []const u8) !void {
            if (try processDisplayFlags(app_config, current_flag)) {
                return;
            }

            if (try processViewportFlags(app_config, current_flag)) {
                return;
            }

            if (try processSystemFlags(app_config, current_flag)) {
                return;
            }
        }

        // Process display-related configuration flags
        fn processDisplayFlags(app_config: *Config, flag: []const u8) !bool {
            if (std.mem.eql(u8, flag, "--icons")) {
                app_config.icons = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--size")) {
                app_config.size = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--permissions")) {
                app_config.perm = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--timestamp")) {
                app_config.time = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--symlinks")) {
                app_config.link = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--group")) {
                app_config.group = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--user")) {
                app_config.user = true;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-icons")) {
                app_config.icons = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-size")) {
                app_config.size = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-permissions")) {
                app_config.perm = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-timestamp")) {
                app_config.time = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-symlinks")) {
                app_config.link = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-group")) {
                app_config.group = false;
                return true;
            } else if (std.mem.eql(u8, flag, "--no-user")) {
                app_config.user = false;
                return true;
            }
            return false;
        }

        // Processes Viewport related configuration flags
        fn processViewportFlags(app_config: *Config, flag: []const u8) !bool {
            if (std.mem.eql(u8, "--fullscreen", flag)) {
                app_config.use_fullscreen = true;
            } else if (std.mem.eql(u8, "--no-fullscreen", flag)) {
                app_config.use_fullscreen = false;
            }

            return false;
        }

        // Process Special Commands that may result in immediate program execution
        fn processSystemFlags(app_config: *Config, flag: []const u8) !bool {
            _ = app_config;
            if (std.mem.eql(u8, flag, "--help")) {
                return true;
            }
            if (std.mem.eql(u8, flag, "--version")) {
                try displayVersionInfo();
                return true;
            }
            return false;
        }

        // Checks if argument is a directory path
        fn isDirectoryArgument(arg: []const u8, source: ConfigSource) bool {
            return arg.len >= 1 and arg[0] != '-' and source == .from_command_line and isValidDirectory(arg);
        }
    };
}

// Checks if the argument is a valid directory, if not, then return false
fn isValidDirectory(arg: []const u8) bool {
    var stat = Stat.stat(arg) catch return false;
    return stat.isDir();
}

// Displays Version Information
fn displayVersionInfo() !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    try writer.print("Sonar v{s}\n", .{APPLICATION_VERSION});
}
