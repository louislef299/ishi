//! An in-memory `Store` implementation used as a test double. It exists to prove
//! the abstraction supports a second backend and to let the command layer and
//! fusion be tested without a running database. It is not wired into the binary.

const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const Document = store.Document;
const Hit = store.Hit;

pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    docs: std.ArrayList(Entry) = .empty,
    next_id: i64 = 1,

    const Entry = struct {
        id: i64,
        sha: ?[]const u8,
        content: []const u8,
        embedding: []f64,
    };

    pub fn init(allocator: std.mem.Allocator) MemoryStore {
        return .{ .allocator = allocator };
    }

    /// Free everything owned by the store. Call this (or `Store.deinit`) once.
    pub fn deinitSelf(self: *MemoryStore) void {
        for (self.docs.items) |e| {
            if (e.sha) |s| self.allocator.free(s);
            self.allocator.free(e.content);
            self.allocator.free(e.embedding);
        }
        self.docs.deinit(self.allocator);
    }

    /// Get a backend-agnostic handle over this store.
    pub fn store(self: *MemoryStore) Store {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: Store.VTable = .{
        .init = vInit,
        .upsert = vUpsert,
        .vectorSearch = vVectorSearch,
        .keywordSearch = vKeywordSearch,
        .deinit = vDeinit,
    };

    fn vInit(_: *anyopaque) anyerror!void {}

    fn vDeinit(ptr: *anyopaque) void {
        cast(ptr).deinitSelf();
    }

    fn vUpsert(ptr: *anyopaque, doc: Document) anyerror!void {
        const s = cast(ptr);
        if (doc.sha) |sha| {
            for (s.docs.items) |e| {
                if (e.sha) |es| {
                    if (std.mem.eql(u8, es, sha)) return; // idempotent on sha
                }
            }
        }
        const content = try s.allocator.dupe(u8, doc.content);
        errdefer s.allocator.free(content);
        const emb = try s.allocator.dupe(f64, doc.embedding);
        errdefer s.allocator.free(emb);
        const sha_copy = if (doc.sha) |x| try s.allocator.dupe(u8, x) else null;
        try s.docs.append(s.allocator, .{
            .id = s.next_id,
            .sha = sha_copy,
            .content = content,
            .embedding = emb,
        });
        s.next_id += 1;
    }

    fn vVectorSearch(ptr: *anyopaque, allocator: std.mem.Allocator, embedding: []const f64, k: usize) anyerror![]Hit {
        return cast(ptr).rank(allocator, k, embedding, null);
    }

    fn vKeywordSearch(ptr: *anyopaque, allocator: std.mem.Allocator, query_text: []const u8, k: usize) anyerror![]Hit {
        return cast(ptr).rank(allocator, k, null, query_text);
    }

    inline fn cast(ptr: *anyopaque) *MemoryStore {
        return @ptrCast(@alignCast(ptr));
    }

    const Scored = struct { id: i64, idx: usize, score: f64 };

    /// Score every doc, sort best-first, hydrate the top `k` into owned Hits.
    /// Keyword mode drops zero-score (non-matching) docs, mirroring `@@`.
    fn rank(self_: *MemoryStore, allocator: std.mem.Allocator, k: usize, embedding: ?[]const f64, query_text: ?[]const u8) ![]Hit {
        var scored: std.ArrayList(Scored) = .empty;
        defer scored.deinit(allocator);

        for (self_.docs.items, 0..) |e, idx| {
            const score = if (embedding) |q| cosine(q, e.embedding) else keywordScore(query_text.?, e.content);
            if (query_text != null and score == 0) continue;
            try scored.append(allocator, .{ .id = e.id, .idx = idx, .score = score });
        }

        std.mem.sort(Scored, scored.items, {}, scoredDesc);

        const n = @min(k, scored.items.len);
        const out = try allocator.alloc(Hit, n);
        errdefer allocator.free(out);
        var filled: usize = 0;
        errdefer for (out[0..filled]) |h| allocator.free(h.content);
        for (0..n) |i| {
            const sc = scored.items[i];
            out[i] = .{
                .id = sc.id,
                .content = try allocator.dupe(u8, self_.docs.items[sc.idx].content),
                .score = sc.score,
            };
            filled += 1;
        }
        return out;
    }
};

fn scoredDesc(_: void, a: MemoryStore.Scored, b: MemoryStore.Scored) bool {
    if (a.score == b.score) return a.id < b.id;
    return a.score > b.score;
}

fn cosine(a: []const f64, b: []const f64) f64 {
    var dot: f64 = 0;
    var na: f64 = 0;
    var nb: f64 = 0;
    const n = @min(a.len, b.len);
    for (0..n) |i| {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if (na == 0 or nb == 0) return 0;
    return dot / (@sqrt(na) * @sqrt(nb));
}

fn keywordScore(query: []const u8, content: []const u8) f64 {
    var score: f64 = 0;
    var it = std.mem.tokenizeAny(u8, query, " \t\n");
    while (it.next()) |tok| {
        if (containsIgnoreCase(content, tok)) score += 1;
    }
    return score;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// Tests //

const testing = std.testing;

fn mkDoc(sha: ?[]const u8, content: []const u8, embedding: []const f64) Document {
    return .{ .sha = sha, .content = content, .embedding = embedding };
}

test "upsert is idempotent on sha" {
    var mem = MemoryStore.init(testing.allocator);
    defer mem.deinitSelf();
    const s = mem.store();

    try s.upsert(mkDoc("abc", "hello world", &.{ 1, 0, 0 }));
    try s.upsert(mkDoc("abc", "hello world", &.{ 1, 0, 0 }));
    try testing.expectEqual(@as(usize, 1), mem.docs.items.len);
}

test "vectorSearch ranks by cosine similarity, best first" {
    var mem = MemoryStore.init(testing.allocator);
    defer mem.deinitSelf();
    const s = mem.store();

    try s.upsert(mkDoc("a", "x axis", &.{ 1, 0, 0 }));
    try s.upsert(mkDoc("b", "y axis", &.{ 0, 1, 0 }));
    try s.upsert(mkDoc("c", "diag", &.{ 1, 1, 0 }));

    const hits = try s.vectorSearch(testing.allocator, &.{ 1, 0, 0 }, 10);
    defer {
        for (hits) |h| testing.allocator.free(h.content);
        testing.allocator.free(hits);
    }
    try testing.expectEqualStrings("x axis", hits[0].content); // perfect match first
    try testing.expectEqual(@as(usize, 3), hits.len);
}

test "keywordSearch returns only matches and honours k" {
    var mem = MemoryStore.init(testing.allocator);
    defer mem.deinitSelf();
    const s = mem.store();

    try s.upsert(mkDoc("a", "zig comptime is great", &.{1}));
    try s.upsert(mkDoc("b", "rust macros", &.{1}));
    try s.upsert(mkDoc("c", "comptime zig metaprogramming", &.{1}));

    const hits = try s.keywordSearch(testing.allocator, "zig comptime", 1);
    defer {
        for (hits) |h| testing.allocator.free(h.content);
        testing.allocator.free(hits);
    }
    try testing.expectEqual(@as(usize, 1), hits.len); // k=1
    // both a and c score 2; the rust doc (score 0) is excluded
    try testing.expect(hits[0].score == 2);
}
