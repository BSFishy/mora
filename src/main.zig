const std = @import("std");
const Module = @import("module.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!

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
    var modules = std.ArrayListUnmanaged(Module).empty;
    defer {
        for (modules.items) |module| {
            module.deinit(allocator);
        }

        modules.deinit(allocator);
    }

    while (try iter.next()) |entry| {
        if (entry.kind != .directory) {
            continue;
        }

        const module = try Module.load(allocator, try dir.openDir(entry.name, .{}));
        try modules.append(allocator, module);
    }

    for (modules.items) |module| {
        std.debug.print("\nnew module\n", .{});

        for (module.tokens) |token| {
            std.debug.print("{s} - {s}\n", .{ @tagName(token.token_type), token.source });
        }
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
