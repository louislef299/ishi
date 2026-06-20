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

//! Reciprocal Rank Fusion — backend-agnostic hybrid ranking that lives above the
//! storage interface. Each arm (vector, keyword, …) returns its hits ordered
//! best-first; fusion combines them by position, sidestepping the problem that
//! arm-native scores live on different scales.

const std = @import("std");
const Hit = @import("store.zig").Hit;

/// A fused result. `content` borrows from the input arms, so the returned slice
/// is valid only while those arms' hits are alive. Caller owns the slice itself.
pub const Fused = struct {
    id: i64,
    content: []const u8,
    score: f64,
};

/// The smoothing constant `k` from the RRF paper; 60 is the pgvector README
/// default and what ishi shipped with.
pub const default_k: f64 = 60;

/// Fuse ranked arms via Reciprocal Rank Fusion: an item's contribution from one
/// arm is `1 / (k + rank)`, where `rank` is its 1-based position in that arm.
/// Contributions sum across arms; results are returned best-first. Caller owns
/// the returned slice.
pub fn fuse(allocator: std.mem.Allocator, arms: []const []const Hit, k: f64) ![]Fused {
    var acc = std.AutoHashMap(i64, Fused).init(allocator);
    defer acc.deinit();

    for (arms) |arm| {
        for (arm, 0..) |h, i| {
            const rank: f64 = @floatFromInt(i + 1);
            const contribution = 1.0 / (k + rank);
            const gop = try acc.getOrPut(h.id);
            if (gop.found_existing) {
                gop.value_ptr.score += contribution;
            } else {
                gop.value_ptr.* = .{ .id = h.id, .content = h.content, .score = contribution };
            }
        }
    }

    const out = try allocator.alloc(Fused, acc.count());
    var it = acc.valueIterator();
    var i: usize = 0;
    while (it.next()) |v| : (i += 1) out[i] = v.*;
    std.mem.sort(Fused, out, {}, lessThanDesc);
    return out;
}

/// Sort best-first: higher score wins; ties break on lower id for determinism.
fn lessThanDesc(_: void, a: Fused, b: Fused) bool {
    if (a.score == b.score) return a.id < b.id;
    return a.score > b.score;
}

// Tests //

const testing = std.testing;

fn hit(id: i64, content: []const u8) Hit {
    return .{ .id = id, .content = content, .score = 0 };
}

test "single arm: score is 1/(k+rank), order preserved" {
    const arm = [_]Hit{ hit(10, "a"), hit(20, "b"), hit(30, "c") };
    const out = try fuse(testing.allocator, &.{&arm}, default_k);
    defer testing.allocator.free(out);

    try testing.expectEqual(@as(usize, 3), out.len);
    try testing.expectEqual(@as(i64, 10), out[0].id);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 61.0), out[0].score, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 62.0), out[1].score, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 63.0), out[2].score, 1e-12);
}

test "overlapping item sums contributions from both arms" {
    const vec = [_]Hit{ hit(1, "x"), hit(2, "y") };
    const kw = [_]Hit{ hit(2, "y"), hit(3, "z") };
    const out = try fuse(testing.allocator, &.{ &vec, &kw }, default_k);
    defer testing.allocator.free(out);

    // id 2 ranks #2 in vec and #1 in kw -> 1/62 + 1/61, beating id 1 and id 3
    // which each appear once at #1/#2 of a single arm.
    try testing.expectEqual(@as(i64, 2), out[0].id);
    try testing.expectApproxEqAbs(@as(f64, 1.0 / 62.0 + 1.0 / 61.0), out[0].score, 1e-12);
    try testing.expectEqual(@as(usize, 3), out.len);
}

test "item present in only one arm keeps that arm's contribution" {
    const vec = [_]Hit{hit(7, "lonely")};
    const kw = [_]Hit{hit(8, "other")};
    const out = try fuse(testing.allocator, &.{ &vec, &kw }, default_k);
    defer testing.allocator.free(out);

    try testing.expectEqual(@as(usize, 2), out.len);
    for (out) |f| try testing.expectApproxEqAbs(@as(f64, 1.0 / 61.0), f.score, 1e-12);
}

test "empty arms produce empty result" {
    const out = try fuse(testing.allocator, &.{ &[_]Hit{}, &[_]Hit{} }, default_k);
    defer testing.allocator.free(out);
    try testing.expectEqual(@as(usize, 0), out.len);
}
