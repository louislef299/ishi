const std = @import("std");

/// Formats an embedding vector as a pgvector-compatible text string "[0.1,0.2,...]".
/// Caller owns the returned slice.
pub fn formatVector(allocator: std.mem.Allocator, embedding: []const f64) ![]u8 {
    var vec: std.ArrayList(u8) = .empty;
    errdefer vec.deinit(allocator);
    try vec.append(allocator, '[');
    for (embedding, 0..) |v, i| {
        if (i > 0) try vec.append(allocator, ',');
        const s = try std.fmt.allocPrint(allocator, "{d}", .{v});
        defer allocator.free(s);
        try vec.appendSlice(allocator, s);
    }
    try vec.append(allocator, ']');
    return try vec.toOwnedSlice(allocator);
}
