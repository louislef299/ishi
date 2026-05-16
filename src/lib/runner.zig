const std = @import("std");

const Runner = @import("../cmd/Flags.zig").Runner;
pub const log = std.log.scoped(.runner);
const retry = @import("retry.zig");

/// Ollama /api/embeddings response: { "embedding": [...] }
const OllamaEmbeddingResponse = struct {
    embedding: []f64,
};

/// OpenAI /v1/embeddings response: { "data": [{ "embedding": [...] }] }
const OpenAIEmbeddingData = struct {
    embedding: []f64,
};

const OpenAIEmbeddingResponse = struct {
    data: []OpenAIEmbeddingData,
};

pub const Opts = struct {
    text: []const u8,
    model_name: []const u8 = "ai/nomic-embed-text-v1.5",
    runner: Runner = Runner.docker,
};

/// Captures the arguments needed by a single embedding attempt so the
/// function can be passed to `retry.retry` which takes `fn(Context) !T`.
const EmbeddingContext = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    opts: Opts,
};

/// Calls the configured model runner's embeddings endpoint and returns the
/// raw embedding vector, retrying with exponential backoff on transient
/// failures. Caller owns the returned slice.
pub fn getEmbedding(
    allocator: std.mem.Allocator,
    io: std.Io,
    opts: Opts,
) ![]f64 {
    const ctx = EmbeddingContext{ .allocator = allocator, .io = io, .opts = opts };
    return switch (opts.runner) {
        .ollama => retry.retry([]f64, io, .{}, ctx, attemptOllamaEmbedding),
        .docker => retry.retry([]f64, io, .{}, ctx, attemptDockerEmbedding),
    };
}

fn attemptOllamaEmbedding(ctx: EmbeddingContext) anyerror![]f64 {
    return getOllamaEmbedding(ctx.allocator, ctx.io, ctx.opts);
}

fn attemptDockerEmbedding(ctx: EmbeddingContext) anyerror![]f64 {
    return getDockerEmbedding(ctx.allocator, ctx.io, ctx.opts);
}

fn getOllamaEmbedding(allocator: std.mem.Allocator, io: std.Io, opts: Opts) ![]f64 {
    const Payload = struct { model: []const u8, prompt: []const u8 };
    const body = try buildBody(allocator, Payload, .{
        .model = opts.model_name,
        .prompt = opts.text,
    });
    defer allocator.free(body);

    const endpoint = "http://localhost:11434/api/embeddings";
    const response_bytes = try postJson(allocator, io, endpoint, body);
    defer allocator.free(response_bytes);

    const parsed = try std.json.parseFromSlice(
        OllamaEmbeddingResponse,
        allocator,
        response_bytes,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    return try allocator.dupe(f64, parsed.value.embedding);
}

fn getDockerEmbedding(allocator: std.mem.Allocator, io: std.Io, opts: Opts) ![]f64 {
    const Payload = struct { model: []const u8, input: []const u8 };
    const body = try buildBody(allocator, Payload, .{
        .model = opts.model_name,
        .input = opts.text,
    });
    defer allocator.free(body);

    const endpoint = "http://localhost:12434/engines/llama.cpp/v1/embeddings";
    const response_bytes = try postJson(allocator, io, endpoint, body);
    defer allocator.free(response_bytes);

    const parsed = try std.json.parseFromSlice(
        OpenAIEmbeddingResponse,
        allocator,
        response_bytes,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    if (parsed.value.data.len == 0) {
        log.err("docker response contained no embedding data", .{});
        return error.RunnerRequestFailed;
    }

    return try allocator.dupe(f64, parsed.value.data[0].embedding);
}

/// POSTs `body` as JSON to `endpoint` and returns the raw response body.
/// Caller owns the returned slice. Returns `error.RunnerRequestFailed` on
/// non-2xx responses (logging the status + body for diagnosis).
fn postJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    endpoint: []const u8,
    body: []const u8,
) ![]u8 {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var response_buf: std.Io.Writer.Allocating = .init(allocator);
    defer response_buf.deinit();

    const result = client.fetch(.{
        .location = .{ .url = endpoint },
        .method = .POST,
        .payload = body,
        .headers = .{ .content_type = .{ .override = "application/json" } },
        .response_writer = &response_buf.writer,
    }) catch |err| {
        log.err("Failed to POST to {s}: {}", .{ endpoint, err });
        return err;
    };

    const status_int = @intFromEnum(result.status);
    if (status_int < 200 or status_int >= 300) {
        log.err("request to {s} failed with status {d}: {s}", .{
            endpoint,
            status_int,
            response_buf.written(),
        });
        return error.RunnerRequestFailed;
    }

    return response_buf.toOwnedSlice();
}

/// Serializes a struct value to a JSON byte string. Caller owns the result.
fn buildBody(
    allocator: std.mem.Allocator,
    comptime T: type,
    value: T,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{});
}
