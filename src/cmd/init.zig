const std = @import("std");
const pg = @import("pg");
const lib = @import("../log.zig");
const flags = @import("flags.zig");

// InitFlags defines the supported CLI flags for the init command.
// Each field name corresponds to a --flag name and its default value
// is used when the flag is not provided by the caller.
const InitFlags = struct {
    target: []const u8 = "localhost",
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var f = InitFlags{};
    flags.parse(&f, args);

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = f.target, .port = 5432 },
        .auth = .{ .username = "postgres", .password = "pgv", .database = "postgres" },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ f.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    std.debug.print("connected to {s}!\n", .{f.target});

    _ = try pool.exec("CREATE EXTENSION vector;", .{});
    _ = try pool.exec("CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));", .{});
    _ = try pool.exec("INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');", .{});
}
