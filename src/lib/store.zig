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

//! The storage seam for ishi. Backends (Postgres today, SQLite later) implement
//! `Store`; everything above it — embedding, git walking, RRF fusion — stays
//! backend-agnostic. Keep this interface small: "the bigger the interface, the
//! weaker the abstraction." Designed as if SQLite is the next implementation, so
//! no Postgres-isms leak through.

const std = @import("std");

/// A unit of stored content: text plus its embedding, with optional git
/// metadata. `sha` and `meta` are optional so the git seed path (a full commit)
/// and the content-only JSON seed path can share a single `upsert`.
pub const Document = struct {
    sha: ?[]const u8 = null,
    content: []const u8,
    embedding: []const f64,
    meta: ?CommitMeta = null,
};

/// Git commit metadata stored alongside a document.
pub const CommitMeta = struct {
    author_name: []const u8,
    author_email: []const u8,
    commit_date_us: i64,
    files_changed: u32,
    insertions: u32,
    deletions: u32,
};

/// A single retrieval result. Arms return these ordered best-first, so a hit's
/// rank is its position in the returned slice (index + 1). `score` is the
/// arm-native score (cosine distance or lexical rank), retained for debugging.
pub const Hit = struct {
    id: i64,
    content: []const u8,
    score: f64,
};

/// Backend-agnostic storage handle (vtable pattern, à la `std.mem.Allocator`).
/// Construct a concrete backend (e.g. `store/postgres.zig`) which returns one of
/// these; commands depend only on `Store`.
pub const Store = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Create/migrate the schema.
        init: *const fn (ptr: *anyopaque) anyerror!void,
        /// Insert or update one document (idempotent on `sha` when present).
        upsert: *const fn (ptr: *anyopaque, doc: Document) anyerror!void,
        /// Nearest-neighbour search over embeddings; returns up to `k` hits,
        /// best-first. Caller owns the returned slice and each `content`.
        vectorSearch: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, embedding: []const f64, k: usize) anyerror![]Hit,
        /// Lexical/keyword search; returns up to `k` hits, best-first. Caller
        /// owns the returned slice and each `content`.
        keywordSearch: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, query_text: []const u8, k: usize) anyerror![]Hit,
        /// Release backend resources (connection pools, file handles).
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn init(self: Store) !void {
        return self.vtable.init(self.ptr);
    }

    pub fn upsert(self: Store, doc: Document) !void {
        return self.vtable.upsert(self.ptr, doc);
    }

    pub fn vectorSearch(self: Store, allocator: std.mem.Allocator, embedding: []const f64, k: usize) ![]Hit {
        return self.vtable.vectorSearch(self.ptr, allocator, embedding, k);
    }

    pub fn keywordSearch(self: Store, allocator: std.mem.Allocator, query_text: []const u8, k: usize) ![]Hit {
        return self.vtable.keywordSearch(self.ptr, allocator, query_text, k);
    }

    pub fn deinit(self: Store) void {
        return self.vtable.deinit(self.ptr);
    }
};
