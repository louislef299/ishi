const std = @import("std");
const builtin = @import("builtin");

comptime {
    requirez("0.16.0");
}

// protip: run zig build --fetch if you don't have some of the remote deps for
// this project
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ishi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // https://github.com/karlseguin/pg.zig
    exe.root_module.addImport(
        "pg",
        b.dependency("pg", .{}).module("pg"),
    );

    // https://zighelp.org/chapter-4/ or `man ld`
    // Zig (like any linker on Unix) automatically prepends lib to the name when
    // searching for the file
    exe.root_module.linkSystemLibrary("git2", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

/// Require a specific version of Zig to build this project.
/// https://github.com/ghostty-org/ghostty/blob/main/src/build/zig.zig
pub fn requirez(comptime required_zig: []const u8) void {
    const current_vsn = builtin.zig_version;
    const required_vsn = std.SemanticVersion.parse(required_zig) catch unreachable;
    if (current_vsn.major != required_vsn.major or
        current_vsn.minor != required_vsn.minor)
    {
        @compileError(std.fmt.comptimePrint(
            "Your Zig version v{} does not meet the required build version of v{}",
            .{ current_vsn, required_vsn },
        ));
    }
}
