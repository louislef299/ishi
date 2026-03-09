// https://www.openmymind.net/Zig-Interfaces/
// https://www.bradcypert.com/interfaces-in-zig/

const std = @import("std");

const Cmd = @This();

allocator: std.mem.Allocator,
summary: []const u8,
flags: *anyopaque,

ptr: *anyopaque,
runFn: *const fn (ptr: *anyopaque, args: []const []const u8) anyerror!void,

// init is a comptime function and acts more like a template as the Zig compiler
// will create a version of init for each type of ptr that the program uses.
fn init(ptr: anytype) Cmd {
    // returns the ptr type(Init, Seed, etc..)
    const T = @TypeOf(ptr);

    // returns a tagged union(std.builtin.Type) which fully describes the type.
    // https://ziglang.org/documentation/0.15.2/std/#std.builtin.Type
    const ptr_info = @typeInfo(T);

    // add comptime checks on the type passed to init
    if (ptr_info != .pointer) @compileError("ptr must be a pointer");
    if (ptr_info.pointer.size != .One) @compileError("ptr must be a single item pointer");

    // need to wrap in a nested structure as Zig lacks anonymous functions
    const gen = struct {
        pub fn run(p: *anyopaque, args: []const []const u8) anyerror!void {
            // use @ptrCast to convert anyopaque pointer into type T. "give me a
            // variable pointing to the same thing as p but treat that like a
            // *T, trust me, I know what I'm doing".

            // use @alignCast to tell the compiler what the alignment is. there
            // are CPU-specific rules for how data must be arranged in memory.
            const self: T = @ptrCast(@alignCast(p));

            // using the std.builtin.Type tagged union, call .pointer.child to
            // get the actual type behind the pointer and execute run!
            return ptr_info.pointer.child.run(self, args);
        }
    };

    return .{
        .ptr = ptr,
        .runFn = gen.run,
    };
}

fn run(self: Cmd, args: []const []const u8) !void {
    return self.runFn(self.ptr, args);
}
