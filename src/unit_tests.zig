const git = @import("lib/git.zig");

// Force the test runner to discover tests in transitively-imported modules.
test {
    @import("std").testing.refAllDecls(@This());
    _ = git;
    _ = @import("lib/store.zig");
    _ = @import("lib/rrf.zig");
    _ = @import("lib/store/memory.zig");
    _ = @import("lib/store/postgres.zig");
}
