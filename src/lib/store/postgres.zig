// Copyright 2026 Louis LeFebvre
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Postgres + pgvector backend for the `Store` interface. All SQL, `pg.Pool`,
//! pgvector, and tsvector specifics live here and nowhere else.

const std = @import("std");
const pg = @import("pg");
const store = @import("../store.zig");
const pgvector = @import("../pgvector.zig");

const Store = store.Store;
const Document = store.Document;
const Hit = store.Hit;

pub const log = std.log.scoped(.postgres);

pub const Config = struct {
    host: []const u8,
    port: u16 = 5432,
    username: []const u8,
    password: []const u8,
    database: []const u8,
    dims: u16,
};

const table_ddl =
    \\CREATE TABLE IF NOT EXISTS items (
    \\ id bigserial PRIMARY KEY,
    \\ sha TEXT UNIQUE,
    \\ content text,
    \\ embedding vector({d}),
    \\ author_name TEXT,
    \\ author_email TEXT,
    \\ commit_date TIMESTAMPTZ,
    \\ files_changed INT,
    \\ insertions INT,
    \\ deletions INT,
    \\ textsearch tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED);
;

const textsearch_index =
    \\CREATE INDEX IF NOT EXISTS items_textsearch_idx ON items USING GIN (textsearch);
;

const PostgresStore = struct {
    allocator: std.mem.Allocator,
    pool: *pg.Pool,
    dims: u16,
};

/// Construct a Postgres-backed `Store`. The caller owns it and must call
/// `store.deinit()`. Logs and returns the error if the connection can't be made.
pub fn create(allocator: std.mem.Allocator, io: std.Io, cfg: Config) !Store {
    const self = try allocator.create(PostgresStore);
    errdefer allocator.destroy(self);

    const pool = pg.Pool.init(io, allocator, .{
        .size = 1,
        .connect = .{ .host = cfg.host, .port = cfg.port },
        .auth = .{ .username = cfg.username, .password = cfg.password, .database = cfg.database },
    }) catch |err| {
        log.err("Failed to connect to {s} (is the db running?): {}", .{ cfg.host, err });
        return err;
    };

    self.* = .{ .allocator = allocator, .pool = pool, .dims = cfg.dims };
    return .{ .ptr = self, .vtable = &vtable };
}

const vtable: Store.VTable = .{
    .init = vInit,
    .upsert = vUpsert,
    .vectorSearch = vVectorSearch,
    .keywordSearch = vKeywordSearch,
    .deinit = vDeinit,
};

inline fn cast(ptr: *anyopaque) *PostgresStore {
    return @ptrCast(@alignCast(ptr));
}

fn vDeinit(ptr: *anyopaque) void {
    const s = cast(ptr);
    s.pool.deinit();
    s.allocator.destroy(s);
}

fn vInit(ptr: *anyopaque) anyerror!void {
    const s = cast(ptr);
    _ = try s.pool.exec("CREATE EXTENSION IF NOT EXISTS vector;", .{});

    // DDL cannot use query parameters — build the SQL on the stack.
    var buf: [1024]u8 = undefined;
    const create_table = try std.fmt.bufPrint(&buf, table_ddl, .{s.dims});
    _ = try s.pool.exec(create_table, .{});
    _ = try s.pool.exec(textsearch_index, .{});
}

fn vUpsert(ptr: *anyopaque, doc: Document) anyerror!void {
    const s = cast(ptr);
    const vec_str = try pgvector.formatVector(s.allocator, doc.embedding);
    defer s.allocator.free(vec_str);

    if (doc.meta) |m| {
        _ = try s.pool.exec(
            "INSERT INTO items (sha, content, embedding, author_name, author_email, commit_date, files_changed, insertions, deletions) VALUES ($1, $2, $3::vector, $4, $5, $6, $7, $8, $9) ON CONFLICT (sha) DO NOTHING",
            .{ doc.sha, doc.content, vec_str, m.author_name, m.author_email, m.commit_date_us, m.files_changed, m.insertions, m.deletions },
        );
    } else {
        _ = try s.pool.exec(
            "INSERT INTO items (content, embedding) VALUES ($1, $2::vector)",
            .{ doc.content, vec_str },
        );
    }
}

fn vVectorSearch(ptr: *anyopaque, allocator: std.mem.Allocator, embedding: []const f64, k: usize) anyerror![]Hit {
    const s = cast(ptr);
    const vec_str = try pgvector.formatVector(allocator, embedding);
    defer allocator.free(vec_str);

    const result = try s.pool.query(
        "SELECT id, content, embedding <=> $1::vector AS score FROM items ORDER BY embedding <=> $1::vector LIMIT $2",
        .{ vec_str, @as(i64, @intCast(k)) },
    );
    defer result.deinit();
    return collect(allocator, result);
}

fn vKeywordSearch(ptr: *anyopaque, allocator: std.mem.Allocator, query_text: []const u8, k: usize) anyerror![]Hit {
    const s = cast(ptr);
    const result = try s.pool.query(
        \\SELECT id, content, ts_rank_cd(textsearch, query)::float8 AS score
        \\FROM items, plainto_tsquery('english', $1) query
        \\WHERE textsearch @@ query
        \\ORDER BY ts_rank_cd(textsearch, query) DESC LIMIT $2
    ,
        .{ query_text, @as(i64, @intCast(k)) },
    );
    defer result.deinit();
    return collect(allocator, result);
}

/// Drain a `(id, content, score)` result set into owned, best-first `Hit`s.
fn collect(allocator: std.mem.Allocator, result: anytype) ![]Hit {
    var list: std.ArrayList(Hit) = .empty;
    errdefer {
        for (list.items) |h| allocator.free(h.content);
        list.deinit(allocator);
    }
    while (try result.next()) |row| {
        const content = try allocator.dupe(u8, try row.get([]const u8, 1));
        errdefer allocator.free(content);
        try list.append(allocator, .{
            .id = try row.get(i64, 0),
            .content = content,
            .score = try row.get(f64, 2),
        });
    }
    return list.toOwnedSlice(allocator);
}

// Tests //
//
// The integration test needs a running pgvector instance (`docker compose up
// -d`). It skips automatically when the database isn't reachable, so
// `zig build test` stays green with no database.

const testing = std.testing;

test "integration: upsert then vector + keyword search round-trip" {
    const allocator = testing.allocator;

    const dims: u16 = 768;
    const db = create(allocator, std.testing.io, .{
        .host = "localhost",
        .username = "postgres",
        .password = "ishi",
        .database = "postgres",
        .dims = dims,
    }) catch return error.SkipZigTest;
    defer db.deinit();

    // Skip (rather than fail) when the DB is unreachable.
    db.init() catch return error.SkipZigTest;

    const emb = try allocator.alloc(f64, dims);
    defer allocator.free(emb);
    @memset(emb, 0);
    emb[0] = 1;

    // Fixed sentinel sha keeps re-runs idempotent (ON CONFLICT DO NOTHING).
    try db.upsert(.{
        .sha = "__ishi_integration_test__",
        .content = "integration test for zig comptime",
        .embedding = emb,
        .meta = .{
            .author_name = "test",
            .author_email = "test@example.com",
            .commit_date_us = 0,
            .files_changed = 1,
            .insertions = 1,
            .deletions = 0,
        },
    });

    const vh = try db.vectorSearch(allocator, emb, 5);
    defer {
        for (vh) |h| allocator.free(h.content);
        allocator.free(vh);
    }
    try testing.expect(vh.len >= 1);

    const kh = try db.keywordSearch(allocator, "comptime", 5);
    defer {
        for (kh) |h| allocator.free(h.content);
        allocator.free(kh);
    }
    try testing.expect(kh.len >= 1);
}
