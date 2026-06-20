const std = @import("std");

const store = @import("../lib/store.zig");
const Flags = @import("./Flags.zig");

pub const log = std.log.scoped(.init);

pub fn run(_: std.mem.Allocator, db: store.Store, f: Flags) !void {
    try db.init();
    std.debug.print("initialized for model '{s}' ({d} dims)\n", .{
        f.model.name, f.model.dims,
    });
}
