const std = @import("std");
const command = @import("command.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Cache = @import("cache.zig");
const Module = @import("module.zig");
const Payload = @import("payload.zig");
const Api = @import("api.zig");

pub fn deploy(allocator: std.mem.Allocator, args: *command.Args) !void {
    defer args.deinit(allocator);

    const rest = args.rest;
    if (rest.len != 1) {
        std.debug.print("Usage: mora-preflight deploy <environment slug>\n", .{});
        return error.invalidInput;
    }

    const environment = rest[0];

    const directory = args.option("dir") orelse ".";

    var cwd = std.fs.cwd();
    var sample = try cwd.openDir(directory, .{ .iterate = true });
    defer sample.close();

    var cache = try Cache.init();
    defer cache.deinit();

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

        var moduleCache = try cache.module(moduleAlloc.allocator(), entry.name);
        defer moduleCache.deinit();

        const dir = try sample.openDir(entry.name, .{ .iterate = true });
        try modules.append(allocator, try parseModule(moduleAlloc.allocator(), &moduleCache, environment, dir, entry.name));

        try moduleCache.write();
    }

    const moduleSlice = try modules.toOwnedSlice(allocator);
    defer allocator.free(moduleSlice);

    var api = try Api.fromConfig(allocator);
    defer api.deinit(allocator);

    const deployment = try api.deploy(allocator, environment, .{ .modules = moduleSlice });
    defer deployment.deinit(allocator);

    std.debug.print("Successfully deployed {s}\n", .{deployment.id});
    std.debug.print("To monitor the deployment, go to {s}/deployment/{s}\n", .{ api.base_url, deployment.id });
}

fn parseModule(allocator: std.mem.Allocator, cache: *Cache.ModuleCache, environment: []const u8, dir: std.fs.Dir, name: []const u8) !Module {
    var module = try Module.init(allocator, dir, name);
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

        try module.insert(allocator, cache, environment, items);
    }

    return module;
}
