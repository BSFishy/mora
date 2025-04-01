const std = @import("std");
const lexer = @import("lexer.zig");

const Self = @This();

contents: []u8,
tokens: []lexer.Token,

pub fn load(allocator: std.mem.Allocator, root_dir: std.fs.Dir) !Self {
    const contents = try root_dir.readFileAlloc(allocator, "module.mora", 2 * 1024 * 1024 * 1024);
    errdefer allocator.free(contents);

    const l = lexer.Lexer.init(allocator);
    var diagnostics = lexer.Diagnostics{};
    const tokens = l.lex(contents, .{ .diagnostics = &diagnostics }) catch |err| {
        if (diagnostics.failure) |failure| {
            try failure.print();
        }

        return err;
    };

    return .{
        .contents = contents,
        .tokens = tokens,
    };
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    allocator.free(self.tokens);
    allocator.free(self.contents);
}
