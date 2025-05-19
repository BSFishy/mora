const std = @import("std");
const lexer = @import("lexer.zig");

const Self = @This();

const NamedBlock = struct {};

const Assignment = struct {};

const Parser = struct {
    contents: []u8,
    tokens: []lexer.Token,

    fn parse(allocator: std.mem.Allocator, root_dir: std.fs.Dir) !Self {
        const contents = try root_dir.readFileAlloc(allocator, "module.mora", 2 * 1024 * 1024 * 1024);
        // errdefer allocator.free(contents);

        const l = lexer.Lexer.init(allocator);
        var diagnostics = lexer.Diagnostics{};
        const tokens = l.lex(contents, .{ .diagnostics = &diagnostics }) catch |err| {
            if (diagnostics.failure) |failure| {
                try failure.print();
            }

            return err;
        };
        // errdefer allocator.free(tokens);

        var self = Parser{
            .contents = contents,
            .tokens = tokens,
        };
        defer self.deinit(allocator);

        return self.parseBlock();
    }

    fn deinit(self: *const Parser, allocator: std.mem.Allocator) void {
        allocator.free(self.contents);
        allocator.free(self.tokens);
    }

    fn parseBlock(self: *Parser) !Self {
        _ = self; // autofix
        return error.unimplemented;
    }
};

name: []const u8,
assignments: []const Assignment,
blocks: []const NamedBlock,

pub fn load(allocator: std.mem.Allocator, root_dir: std.fs.Dir) !Self {
    return Parser.parse(allocator, root_dir);
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    allocator.free(self.assignments);
    allocator.free(self.blocks);
}
