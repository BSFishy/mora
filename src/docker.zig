const std = @import("std");

pub fn build(allocator: std.mem.Allocator, moduleName: []const u8, path: []const u8) ![]const u8 {
    const basename = std.fs.path.basename(path);

    const tag = try std.fmt.allocPrint(allocator, "mora-{s}-{s}:latest", .{ moduleName, basename });
    errdefer allocator.free(tag);

    var child = std.process.Child.init(&.{ "docker", "build", "-t", tag, path }, allocator);

    try child.spawn();
    const term = try child.wait();

    // TODO: capture stdout and stderr and print them on error
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.invalidExitCode;
            }
        },
        else => return error.invalidTermination,
    }

    return tag;
}

pub fn save(allocator: std.mem.Allocator, tag: []const u8, out: []const u8) !void {
    var child = std.process.Child.init(&.{ "docker", "save", tag, "-o", out }, allocator);

    try child.spawn();
    const term = try child.wait();

    // TODO: capture stdout and stderr and print them on error
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.invalidExitCode;
            }
        },
        else => return error.invalidTermination,
    }
}
