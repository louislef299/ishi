const std = @import("std");

pub const log = std.log.scoped(.query);
const runner = @import("../lib/runner.zig");
const rrf = @import("../lib/rrf.zig");
const store = @import("../lib/store.zig");
const Flags = @import("Flags.zig");

/// How many candidates to pull from each arm before fusing.
const candidates_per_arm = 20;
/// How many fused results to print.
const max_results = 3;

pub fn run(allocator: std.mem.Allocator, db: store.Store, f: Flags) !void {
    if (f.query.len == 0) {
        log.err("query text is required: ishi query \"your question here\"", .{});
        std.process.exit(1);
    }

    std.debug.print("querying: \"{s}\"\n\n", .{f.query});

    // Embed the query text via the model runner.
    const embedding = try runner.getEmbedding(allocator, f.io, .{
        .model_name = f.model.name,
        .text = f.query,
        .runner = f.runner,
    });
    defer allocator.free(embedding);

    // Two arms — semantic (vector) and keyword (lexical) — fused with RRF.
    const vec_hits = try db.vectorSearch(allocator, embedding, candidates_per_arm);
    defer {
        for (vec_hits) |h| allocator.free(h.content);
        allocator.free(vec_hits);
    }

    const kw_hits = try db.keywordSearch(allocator, f.query, candidates_per_arm);
    defer {
        for (kw_hits) |h| allocator.free(h.content);
        allocator.free(kw_hits);
    }

    // `fused` borrows content from the arms above, so it must be freed first
    // (declared last → freed first under LIFO defers) and printed before them.
    const fused = try rrf.fuse(allocator, &.{ vec_hits, kw_hits }, rrf.default_k);
    defer allocator.free(fused);

    const limit = @min(@as(usize, max_results), fused.len);
    for (fused[0..limit], 1..) |result, rank| {
        std.debug.print("{d}. ({d:.4}) {s}\n", .{ rank, result.score, result.content });
    }

    if (fused.len == 0) {
        std.debug.print("no results found. have you run 'ishi seed' yet?\n", .{});
    }
}
