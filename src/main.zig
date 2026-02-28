const std = @import("std");
const init_cmd = @import("cmd/init.zig");

const usage =
    \\pgv - pgvector CLI
    \\
    \\Usage: pgv <command> [options]
    \\
    \\Commands:
    \\  init    Initialize the pg database with pgvector
    \\
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print(usage, .{});
        return;
    }

    const Cmd = enum { init };
    const cmd = std.meta.stringToEnum(Cmd, args[1]) orelse {
        std.debug.print(usage, .{});
        return;
    };

    switch (cmd) {
        .init => try init_cmd.run(allocator, args[2..]),
    }
}
