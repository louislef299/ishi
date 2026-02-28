const std = @import("std");
const yazap = @import("yazap");

pub fn create(app: *yazap.App) !yazap.Command {
    var cmd_init = app.createCommand(
        "init",
        "Initialize the pg database with pgvector",
    );
    try cmd_init.addArg(yazap.Arg.singleValueOption("target", 't', "The name of the target db hostname"));
    return cmd_init;
}

pub fn run(m: *const yazap.ArgMatches) !void {
    // -t || --target
    const target = m.getSingleValue("target") orelse "localhost";

    std.debug.print("target: {s}\n", .{target});
}
