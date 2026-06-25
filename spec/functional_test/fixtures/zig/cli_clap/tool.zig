const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help          Display help.
        \\-p, --port <u16>    Port to bind.
        \\-v, --verbose       Verbose output.
        \\<FILE>              Input file.
    );
    _ = params;
    const token = std.process.getEnvVarOwned(allocator, "API_TOKEN");
    _ = token;
}
