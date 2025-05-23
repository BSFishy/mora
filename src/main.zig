const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Module = @import("module.zig");
const Payload = @import("payload.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    const allocator = debug_allocator.allocator();
    defer {
        const check = debug_allocator.deinit();
        if (check == .leak) {
            std.process.exit(1);
        }
    }

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

    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    const moduleSlice = try modules.toOwnedSlice(allocator);
    defer allocator.free(moduleSlice);

    try std.json.stringify(Payload{ .modules = moduleSlice }, .{}, writer);
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
