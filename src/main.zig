// https://ziglang.org/documentation/0.15.2/std
const std = @import("std");
const yazap = @import("yazap");

const App = yazap.App;

// https://codeberg.org/ziglang/zig/pulls/30644
pub fn main(init: std.process.Init) !void {
    var app = App.init(init.gpa, "pgv", "My pgvector tool");
    defer app.deinit();

    var pgv = app.rootCommand();
    pgv.setProperty(.help_on_empty_args);

    try pgv.addSubcommand(app.createCommand(
        "init",
        "Initialize the pg database with pgvector",
    ));

    const matches = try app.parseProcess(init.io, init.minimal.args);
    if (matches.containsArg("init")) {
        std.debug.print("Initilize pg database", .{});
        return;
    }
}
