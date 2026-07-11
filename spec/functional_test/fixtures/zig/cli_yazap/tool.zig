const std = @import("std");
const yazap = @import("yazap");
const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var app = App.init(allocator, "tool", "Example CLI tool");
    defer app.deinit();

    var root_cmd = app.rootCommand();
    try root_cmd.addArg(Arg.booleanOption("verbose", 'v', "Enable verbose output"));
    try root_cmd.addArg(Arg.positional("input", "Input file", null));

    var build_cmd = app.createCommand("build", "Build the project");
    try build_cmd.addArg(Arg.booleanOption("release", 'r', "Build in release mode"));
    try build_cmd.addArg(Arg.singleValueOption("output", 'o', "Output path"));
    try root_cmd.addSubcommand(build_cmd);

    const matches = try app.parseProcess();
    _ = matches;

    const token = std.process.getEnvVarOwned(allocator, "API_TOKEN");
    _ = token;
}
