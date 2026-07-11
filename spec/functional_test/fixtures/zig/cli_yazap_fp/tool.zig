const std = @import("std");
const yazap = @import("yazap");
const App = yazap.App;
const Arg = yazap.Arg;

// The generic `cmd` variable is reused across two subcommands. Flags added
// to `cmd` BEFORE it is reassigned must resolve to the command that was
// bound to it AT THAT LINE (build), never to whichever command is assigned
// LAST in the file (test).
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = App.init(allocator, "tool", "Example CLI tool");
    defer app.deinit();

    var cmd = app.createCommand("build", "Build the project");
    try cmd.addArg(Arg.booleanOption("release", 'r', "Build in release mode"));

    cmd = app.createCommand("test", "Run tests");
    try cmd.addArg(Arg.booleanOption("verbose", 'v', "Verbose output"));

    const matches = try app.parseProcess();
    _ = matches;
}
