const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Module = @import("module.zig");
const Payload = @import("payload.zig");
const command = @import("command.zig");

fn default(allocator: std.mem.Allocator, args: *command.Args) !void {
    defer args.deinit(allocator);

    std.debug.print("Please use a subcommand\n", .{});
}

fn deploy(allocator: std.mem.Allocator, args: *command.Args) !void {
    defer args.deinit(allocator);

    var cwd = std.fs.cwd();
    var sample = try cwd.openDir("sample", .{ .iterate = true });
    defer sample.close();

    var modules = std.ArrayListUnmanaged(Module).empty;
    errdefer modules.deinit(allocator);

    // using an arena allocator for modules too because they contain ast nodes
    // and i dont wanna pollute that code with deinit stuff
    var moduleAlloc = std.heap.ArenaAllocator.init(allocator);
    defer moduleAlloc.deinit();

    var iter = sample.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) {
            continue;
        }

        const dir = try sample.openDir(entry.name, .{ .iterate = true });
        try modules.append(allocator, try parseModule(moduleAlloc.allocator(), dir, entry.name));
    }

    const moduleSlice = try modules.toOwnedSlice(allocator);
    defer allocator.free(moduleSlice);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const header_buffer = try allocator.alloc(u8, 2 * 1024);
    defer allocator.free(header_buffer);

    var request = try client.open(.POST, try std.Uri.parse("http://127.0.0.1:8080/api/v1/deployment"), .{ .server_header_buffer = header_buffer });
    defer request.deinit();

    request.transfer_encoding = .chunked;

    try request.send();

    const writer = request.writer();
    try std.json.stringify(Payload{ .modules = moduleSlice }, .{}, writer);

    try request.finish();
    try request.wait();

    const response = request.response;
    if (response.status != .ok) {
        std.debug.print("request errored: {s}\n", .{@tagName(response.status)});

        const reader = request.reader();

        const stdout = std.io.getStdOut();
        defer stdout.close();

        const stdoutWriter = stdout.writer();

        var fifo = std.fifo.LinearFifo(u8, .Dynamic).init(allocator);
        defer fifo.deinit();

        try fifo.pump(reader, stdoutWriter);

        return error.invalidStatus;
    }

    std.debug.print("Success\n", .{});
}

const deploy_cmd = command.Command(.{
    .name = "deploy",
    .rest = true,
    .handler = deploy,
});

const Command = command.Command(.{
    .name = "mora-preflight",
    .flags = .{
        .help = .{ .short = 'h', .long = "help", .help = "display this help text" },
    },
    .subcommands = &.{deploy_cmd},
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

fn parseModule(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8) !Module {
    var module = try Module.init(allocator, name);
    errdefer module.deinit(allocator);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        if (!std.mem.endsWith(u8, entry.name, ".mora")) {
            continue;
        }

        const content = try dir.readFileAlloc(allocator, entry.name, 2 * 1024 * 1024 * 1024);
        defer allocator.free(content);

        var l = lexer.Lexer.init(allocator);

        const tokens = try l.lex(content, .{});
        defer allocator.free(tokens);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const items = try parser.parse(arena.allocator(), tokens);

        try module.insert(allocator, items);
    }

    return module;
}
