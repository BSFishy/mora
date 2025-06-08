const std = @import("std");
const command = @import("command.zig");

fn default(allocator: std.mem.Allocator, args: *command.Args) !void {
    defer args.deinit(allocator);

    std.debug.print("Please use a subcommand\n", .{});
}

const deploy = @import("deploy.zig").deploy;
const deploy_cmd = command.Command(.{
    .name = "deploy",
    .rest = true,
    .handler = deploy,
});

const auth = @import("auth.zig").auth;
const auth_cmd = command.Command(.{
    .name = "auth",
    .rest = true,
    .handler = auth,
});

const Command = command.Command(.{
    .name = "mora-preflight",
    .flags = .{
        .help = .{ .short = 'h', .long = "help", .help = "display this help text" },
    },
    .subcommands = &.{ auth_cmd, deploy_cmd },
    .handler = default,
});

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    const allocator = debug_allocator.allocator();
    defer {
        const check = debug_allocator.deinit();
        if (check == .leak) {
            @panic("memory leak");
        }
    }

    try Command.parse(allocator);
}
