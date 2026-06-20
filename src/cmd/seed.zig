const std = @import("std");

pub const log = std.log.scoped(.seed);
const git = @import("../lib/git.zig");
const runner = @import("../lib/runner.zig");
const store = @import("../lib/store.zig");
const Flags = @import("Flags.zig");

const SeedEntry = struct {
    id: []const u8,
    text: []const u8,
};

pub fn run(allocator: std.mem.Allocator, db: store.Store, f: Flags) !void {
    if (f.jsonpath.len == 0) {
        log.debug("seeding from git...", .{});
        try seedFromGit(allocator, db, f);
    } else {
        log.debug("seeding from json...", .{});
        try seedFromJson(allocator, db, f);
    }
}

fn seedFromGit(allocator: std.mem.Allocator, db: store.Store, f: Flags) !void {
    log.info("Walking up to {d} commits...", .{f.limit});

    const commits = git.walkCommits(allocator, ".", f.limit) catch |err| {
        log.err("Failed to walk git history: {}", .{err});
        std.process.exit(1);
    };
    defer {
        for (commits) |*ci| {
            @constCast(ci).deinit();
        }
        allocator.free(commits);
    }

    log.info("Found {d} commits, seeding...", .{commits.len});

    for (commits) |ci| {
        const sha_str = &ci.sha;
        log.info("embedding {s}...", .{sha_str});

        // Combine commit message and diff patch for embedding.
        // Truncate final content to ~1024 bytes to stay within llama.cpp's
        // default 512-token physical batch size (~4 bytes/token for nomic-embed-text).
        const max_embed_len: usize = 1024;

        // Metadata + message overhead is ~200-300 bytes, so cap the patch early.
        const patch = ci.diff_patch[0..@min(ci.diff_patch.len, max_embed_len)];
        const full_content = try ci.format(allocator, patch);
        defer allocator.free(full_content);

        const content = full_content[0..@min(full_content.len, max_embed_len)];
        log.debug("Git Embedding:\t{s}", .{content});

        const embedding = runner.getEmbedding(allocator, f.io, .{
            .model_name = f.model.name,
            .text = content,
            .runner = f.runner,
        }) catch |err| {
            log.warn("skipping {s}: {}", .{ sha_str, err });
            continue;
        };
        defer allocator.free(embedding);

        try db.upsert(.{
            .sha = ci.sha[0..],
            .content = content,
            .embedding = embedding,
            .meta = .{
                .author_name = ci.author_name,
                .author_email = ci.author_email,
                // Stored as microseconds; libgit2 reports seconds.
                .commit_date_us = ci.author_date * 1_000_000,
                .files_changed = @intCast(ci.files_changed),
                .insertions = @intCast(ci.insertions),
                .deletions = @intCast(ci.deletions),
            },
        });
        log.info("  seeded {s}", .{sha_str});
    }
}

fn seedFromJson(allocator: std.mem.Allocator, db: store.Store, f: Flags) !void {
    // Read the seed file from disk.
    const seed_data = std.Io.Dir.cwd().readFileAlloc(
        f.io,
        f.jsonpath,
        allocator,
        std.Io.Limit.limited(1024 * 1024),
    ) catch |err| {
        log.err("Failed to read '{s}': {}", .{ f.jsonpath, err });
        std.process.exit(1);
    };
    defer allocator.free(seed_data);

    const parsed = try std.json.parseFromSlice(
        []SeedEntry,
        allocator,
        seed_data,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    for (parsed.value) |entry| {
        log.info("embedding '{s}'...", .{entry.id});

        // Call the model runner to generate the embedding vector.
        const embedding = try runner.getEmbedding(allocator, f.io, .{
            .model_name = f.model.name,
            .text = entry.text,
            .runner = f.runner,
        });
        defer allocator.free(embedding);

        try db.upsert(.{ .content = entry.text, .embedding = embedding });
        log.info("  seeded '{s}'", .{entry.id});
    }
}
