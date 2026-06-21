const std = @import("std");

const Flags = @import("./cmd/Flags.zig");
const git = @import("lib/git.zig");
const postgres = @import("lib/store/postgres.zig");
const init_cmd = @import("cmd/init.zig");
pub const log = std.log.scoped(.ishi);
const query_cmd = @import("cmd/query.zig");
const seed_cmd = @import("cmd/seed.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const f = try Flags.init(allocator, init);
    defer f.deinit();

    const db = postgres.create(allocator, init.io, .{
        .host = f.target,
        .username = f.username,
        .password = f.password,
        .database = f.database,
        .dims = f.model.dims,
    }) catch std.process.exit(1);
    defer db.deinit();

    switch (f.cmd) {
        .init => try init_cmd.run(allocator, db, f),
        .seed => seed_cmd.run(allocator, db, f) catch |err| {
            log.err("seed command failed: {}", .{err});
            return;
        },
        .query => try query_cmd.run(allocator, db, f),
    }
}
