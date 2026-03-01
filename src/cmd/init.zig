const std = @import("std");
const pg = @import("pg");
const flags = @import("flags.zig");
const lib = @import("../log.zig");
const models = @import("../models.zig");

// InitFlags defines the supported CLI flags for the init command.
// Each field name corresponds to a --flag name and its default value
// is used when the flag is not provided by the caller.
const InitFlags = struct {
    username: []const u8 = "postgres",
    password: []const u8 = "pgv",
    database: []const u8 = "postgres",
    target: []const u8 = "localhost",
    model: []const u8 = "nomic-embed-text",

    pub const descriptions = struct {
        pub const username = "Username used to connect to the postgres database";
        pub const password = "Password used to connect to the postgres database";
        pub const database = "Target postgres database to connect to";
        pub const target = "Network address of the postgres database";
        pub const model = "Ollama embedding model to configure the vector column for";
    };
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var f = InitFlags{};
    try flags.parse(&f, args);

    // Validate the model before spending time on a connection.
    const model = models.find(f.model) orelse {
        lib.log.err("Unknown model '{s}'. Supported models:", .{f.model});
        for (models.ollama) |m| lib.log.err("  {s}", .{m.name});
        std.posix.exit(1);
    };

    var pool = pg.Pool.init(allocator, .{
        .size = 1,
        .connect = .{ .host = f.target, .port = 5432 },
        .auth = .{ .username = f.username, .password = f.password, .database = f.database },
    }) catch |err| {
        lib.log.err("Failed to connect to {s}: {}", .{ f.target, err });
        std.posix.exit(1);
    };
    defer pool.deinit();

    _ = try pool.exec("CREATE EXTENSION IF NOT EXISTS vector;", .{});

    // DDL cannot use query parameters — build the SQL on the stack.
    var buf: [256]u8 = undefined;
    const create_table = try std.fmt.bufPrint(
        &buf,
        "CREATE TABLE IF NOT EXISTS items (id bigserial PRIMARY KEY, embedding vector({d}));",
        .{model.dims},
    );
    _ = try pool.exec(create_table, .{});

    std.debug.print("initialized '{s}' for model '{s}' ({d} dims)\n", .{
        f.target, model.name, model.dims,
    });
}
