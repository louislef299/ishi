const std = @import("std");
const pg = @import("pg");

pub const log = std.log.scoped(.query);
const runner = @import("../lib/runner.zig");
const pgvector = @import("../lib/pgvector.zig");
const Flags = @import("Flags.zig");

pub fn run(allocator: std.mem.Allocator, pool: *pg.Pool, f: Flags) !void {
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

    // Format as pgvector-compatible string.
    const vec_str = try pgvector.formatVector(allocator, embedding);
    defer allocator.free(vec_str);

    // Hybrid search: combine vector (cosine) and BM25 (tsvector) results
    // via Reciprocal Rank Fusion. k=60 follows the pgvector README default.
    var result = try pool.query(
        \\WITH semantic_search AS (
        \\    SELECT id, RANK() OVER (ORDER BY embedding <=> $1::vector) AS rank
        \\    FROM items ORDER BY embedding <=> $1::vector LIMIT 20
        \\),
        \\keyword_search AS (
        \\    SELECT id, RANK() OVER (ORDER BY ts_rank_cd(textsearch, query) DESC) AS rank
        \\    FROM items, plainto_tsquery('english', $2) query
        \\    WHERE textsearch @@ query
        \\    ORDER BY ts_rank_cd(textsearch, query) DESC LIMIT 20
        \\)
        \\SELECT i.content,
        \\       COALESCE(1.0 / (60 + ss.rank), 0.0)
        \\     + COALESCE(1.0 / (60 + ks.rank), 0.0) AS score
        \\FROM semantic_search ss
        \\FULL OUTER JOIN keyword_search ks ON ss.id = ks.id
        \\JOIN items i ON i.id = COALESCE(ss.id, ks.id)
        \\ORDER BY score DESC LIMIT 3
    , .{ vec_str, f.query });
    defer result.deinit();

    var rank: u8 = 1;
    while (try result.next()) |row| {
        const content = try row.get([]const u8, 0);
        const score = try row.get(f64, 1);
        std.debug.print("{d}. ({d:.4}) {s}\n", .{ rank, score, content });
        rank += 1;
    }

    if (rank == 1) {
        std.debug.print("no results found. have you run 'ishi seed' yet?\n", .{});
    }
}
