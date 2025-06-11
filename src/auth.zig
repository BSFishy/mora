const std = @import("std");
const command = @import("command.zig");
const Api = @import("api.zig");

pub const Config = struct {
    domain: []const u8,
    token: []const u8,
};

pub fn auth(allocator: std.mem.Allocator, args: *command.Args) !void {
    defer args.deinit(allocator);

    if (args.rest.len != 2) {
        std.debug.print("Usage: mora-preflight auth <domain> <token>\n", .{});
        return error.invalidInput;
    }

    const config = Config{
        .domain = args.rest[0],
        .token = args.rest[1],
    };

    var api = try Api.init(allocator, config.domain, config.token);
    defer api.deinit(allocator);

    api.ping(allocator) catch |err| {
        std.debug.print("Failed to connect to server successfully. Please make sure you put in your details correctly.\n", .{});
        return err;
    };

    const data_dir = try std.fs.getAppDataDir(allocator, "mora");
    defer allocator.free(data_dir);

    std.fs.makeDirAbsolute(data_dir) catch {};
    var dir = try std.fs.openDirAbsolute(data_dir, .{});
    defer dir.close();

    var file = try dir.createFile("config.json", .{ .mode = 0o600 });
    defer file.close();

    const writer = file.writer();
    try std.json.stringify(config, .{}, writer);

    std.debug.print("Successfully configured authentication\n", .{});
}
