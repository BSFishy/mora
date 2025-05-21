const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Module = @import("module.zig");

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
    var sample = try cwd.openDir("sample", .{});
    defer sample.close();

    var my_module1 = try sample.openDir("my_module1", .{});
    defer my_module1.close();

    const content = try my_module1.readFileAlloc(allocator, "module.mora", 2 * 1024 * 1024 * 1024);
    defer allocator.free(content);

    var l = lexer.Lexer.init(allocator);

    const tokens = try l.lex(content, .{});
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const items = try parser.parse(arena.allocator(), tokens);

    const module = try Module.init(allocator, items);
    defer module.deinit(allocator);

    for (module.services) |service| {
        std.debug.print("{s} - {any}\n", .{ service.name, service.image });
    }
}
