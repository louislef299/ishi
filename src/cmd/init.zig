const std = @import("std");
const pg = @import("pg");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var target: []const u8 = "localhost";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--target") or std.mem.eql(u8, args[i], "-t")) {
            if (i + 1 < args.len) {
                target = args[i + 1];
                i += 1;
            }
        }
    }

    var pool = try pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = target, .port = 5432 },
        .auth = .{ .username = "postgres", .password = "pgv", .database = "postgres" },
    });
    defer pool.deinit();

    std.debug.print("connected to {s}\n", .{target});
}
