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

const std = @import("std");

const Flags = @import("./cmd/Flags.zig");
const git = @import("lib/git.zig");
const postgres = @import("lib/store/postgres.zig");
const init_cmd = @import("cmd/init.zig");
pub const log = std.log.scoped(.ishi);
const query_cmd = @import("cmd/query.zig");
const seed_cmd = @import("cmd/seed.zig");

// Force the test runner to discover tests in transitively-imported modules.
test {
    @import("std").testing.refAllDecls(@This());
    _ = git;
    _ = @import("lib/store.zig");
    _ = @import("lib/rrf.zig");
    _ = @import("lib/store/memory.zig");
    _ = @import("lib/store/postgres.zig");
}

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const f = try Flags.init(allocator, init);
    defer f.deinit();

    const db = postgres.create(allocator, init.io, .{
        .host = f.target,
        .username = f.username,
        .password = f.password,
        .database = f.database,
        .dims = f.model.dims,
    }) catch std.process.exit(1);
    defer db.deinit();

    switch (f.cmd) {
        .init => try init_cmd.run(allocator, db, f),
        .seed => seed_cmd.run(allocator, db, f) catch |err| {
            log.err("seed command failed: {}", .{err});
            return;
        },
        .query => try query_cmd.run(allocator, db, f),
    }
}
