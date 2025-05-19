const std = @import("std");
const Block = @import("block.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    const allocator = debug_allocator.allocator();
    defer {
        const check = debug_allocator.deinit();
        if (check == .leak) {
            std.process.exit(1);
        }
    }

    const dir = try std.fs.cwd().openDir("sample", .{ .iterate = true });
    var iter = dir.iterate();
    var blocks = std.ArrayListUnmanaged(Block).empty;
    defer {
        for (blocks.items) |block| {
            block.deinit(allocator);
        }

        blocks.deinit(allocator);
    }

    while (try iter.next()) |entry| {
        if (entry.kind != .directory) {
            continue;
        }

        const module = try Block.load(allocator, try dir.openDir(entry.name, .{}));
        try blocks.append(allocator, module);
    }

    for (blocks.items) |_| {
        std.debug.print("\nnew module\n", .{});

        // for (module.tokens) |token| {
        //     std.debug.print("{s} - {s}\n", .{ @tagName(token.token_type), token.source });
        // }
    }
}
