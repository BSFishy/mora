const std = @import("std");

const Cache = @import("cache.zig");
const functions = @import("functions.zig");
const lexer = @import("lexer.zig");

pub const Item = union(enum) {
    statement: Statement,
    block: Block,

    pub fn asStatement(self: Item) ?Statement {
        return switch (self) {
            .statement => |statement| statement,
            else => null,
        };
    }

    pub fn asBlock(self: Item) ?Block {
        return switch (self) {
            .block => |block| block,
            else => null,
        };
    }
};

pub const Statement = struct {
    identifier: []const u8,
    expression: Expression,
};

pub const Block = struct {
    identifier: ListExpression,
    items: []Item,
};

pub const ReturnValue = union(enum) {
    unknown,
    identifier: []const u8,
    string: []const u8,

    pub fn asIdentifier(self: ReturnValue) ?[]const u8 {
        return switch (self) {
            .identifier => |ident| ident,
            else => null,
        };
    }

    pub fn asString(self: ReturnValue) ?[]const u8 {
        return switch (self) {
            .string => |string| string,
            else => null,
        };
    }

    pub fn asExpression(self: ReturnValue) !Expression {
        return .{ .atom = try self.asAtom() };
    }

    pub fn asAtom(self: ReturnValue) !Atom {
        return switch (self) {
            .unknown => error.invalidExpression,
            .identifier => |ident| .{ .identifier = ident },
            .string => |string| .{ .string = string },
        };
    }
};

pub const EvaluationContext = struct {
    allocator: std.mem.Allocator,
    cache: *Cache.ModuleCache,
    environment: []const u8,
    module: []const u8,
    service: []const u8,
    dir: std.fs.Dir,
};

pub const Expression = union(enum) {
    list: ListExpression,
    atom: Atom,

    pub fn asList(self: Expression) ?ListExpression {
        return switch (self) {
            .list => |list| list,
            else => null,
        };
    }

    pub fn asAtom(self: Expression) ?Atom {
        return switch (self) {
            .atom => |atom| atom,
            else => null,
        };
    }

    pub fn eagerEvaluate(self: Expression, ctx: *const EvaluationContext) anyerror!Expression {
        switch (self) {
            .list => |list| {
                if (list.len < 1) {
                    return error.invalidFunction;
                }

                var expressions = std.ArrayListUnmanaged(Expression).empty;
                errdefer expressions.deinit(ctx.allocator);

                for (list) |item| {
                    try expressions.append(ctx.allocator, try item.eagerEvaluate(ctx));
                }

                const name_expression = expressions.items[0];
                if (name_expression.asAtom()) |name_atom| {
                    if (name_atom.asIdentifier()) |name_identifier| {
                        if (std.mem.eql(u8, name_identifier, "image")) {
                            defer expressions.deinit(ctx.allocator);
                            return functions.image(ctx, expressions.items[1..]);
                        } else if (std.mem.eql(u8, name_identifier, "read_file")) {
                            defer expressions.deinit(ctx.allocator);

                            if (expressions.items.len != 2) {
                                return error.invalidReadFileCall;
                            }

                            const file_name_expression = expressions.items[1];
                            const file_name_atom = file_name_expression.asAtom() orelse return error.invalidReadFileName;
                            const file_name = file_name_atom.asString() orelse return error.invalidReadFileName;

                            const contents = try ctx.dir.readFileAlloc(ctx.allocator, file_name, 2 * 1024 * 1024 * 1024);
                            errdefer ctx.allocator.free(contents);

                            const encoder = std.base64.standard.Encoder;
                            const b64_len = encoder.calcSize(contents.len);

                            const file = try ctx.allocator.alloc(u8, b64_len);
                            errdefer ctx.allocator.free(file);

                            const file_contents = encoder.encode(file, contents);
                            return .{ .atom = .{ .file = file_contents } };
                        }
                    }
                }

                return .{
                    .list = try expressions.toOwnedSlice(ctx.allocator),
                };
            },
            .atom => return self,
        }

        if (try self.evaluate(ctx)) |rv| {
            return try rv.asExpression();
        }

        return self;
    }
};

pub const ListExpression = []Expression;

pub const Atom = union(enum) {
    string: []const u8,
    identifier: []const u8,
    // base64 encoded file
    file: []const u8,
    // representing numbers as the raw string that comes from the source code.
    // no need to actually parse it out here, can just send it directly to the
    // manager
    number: []const u8,

    pub fn asString(self: Atom) ?[]const u8 {
        return switch (self) {
            .string => |string| string,
            else => null,
        };
    }

    pub fn asIdentifier(self: Atom) ?[]const u8 {
        return switch (self) {
            .identifier => |identifier| identifier,
            else => null,
        };
    }

    pub fn asNumber(self: Atom) ?[]const u8 {
        return switch (self) {
            .number => |number| number,
            else => null,
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) ![]Item {
    return Parser.parse(allocator, tokens);
}

fn optional(T: type, val: anyerror!T) !?T {
    if (val) |v| {
        return v;
    } else |err| {
        if (err != error.invalidInput) {
            return err;
        }
    }

    return null;
}

const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tokens: []lexer.Token,

    // the stack system isn't ideal because it will indefinitely grow with
    // successfully parsed nodes, but tbh not a huge issue for mvp. this is
    // honestly just kinda a shitty recursive descent parser and it will fail to
    // scale at some point. will build something better when it needs to be
    // battle-hardened
    i: usize = 0,
    stack: std.ArrayListUnmanaged(usize),

    fn init(allocator: std.mem.Allocator, tokens: []lexer.Token) Self {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .stack = std.ArrayListUnmanaged(usize).empty,
        };
    }

    pub fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) ![]Item {
        var self = Self.init(allocator, tokens);

        const items = try self.parseItems();
        if (self.i != self.tokens.len) {
            return error.invalidInput;
        }

        return items;
    }

    fn peek(self: *const Self) ?lexer.Token {
        if (self.i >= self.tokens.len) {
            return null;
        }

        return self.tokens[self.i];
    }

    fn consume(self: *Self, token_type: lexer.TokenType) !lexer.Token {
        return self.optionalConsume(token_type) orelse error.invalidInput;
    }

    fn optionalConsume(self: *Self, token_type: lexer.TokenType) ?lexer.Token {
        if (self.i >= self.tokens.len) {
            return null;
        }

        const token = self.tokens[self.i];
        if (token.token_type == token_type) {
            self.i += 1;
            return token;
        }

        return null;
    }

    fn oneOf(self: *Self, comptime tokens: []const lexer.TokenType) !lexer.Token.MatchedType(tokens) {
        return self.optionalOneOf(tokens) orelse error.invalidInput;
    }

    fn optionalOneOf(self: *Self, comptime tokens: []const lexer.TokenType) ?lexer.Token.MatchedType(tokens) {
        if (self.i >= self.tokens.len) {
            return null;
        }

        const token = self.tokens[self.i];
        if (token.match(tokens)) |matched| {
            self.i += 1;
            return matched;
        }

        return null;
    }

    fn enter(self: *Self) !void {
        try self.stack.append(self.allocator, self.i);
    }

    fn rollback(self: *Self) void {
        self.i = self.stack.pop() orelse unreachable;
    }

    fn parseItems(self: *Self) ![]Item {
        try self.enter();
        errdefer self.rollback();

        var items = std.ArrayListUnmanaged(Item).empty;
        while (try optional(Item, self.parseItem())) |item| {
            try items.append(self.allocator, item);
        }

        return items.toOwnedSlice(self.allocator);
    }

    fn parseItem(self: *Self) !Item {
        try self.enter();
        errdefer self.rollback();

        if (try optional(Statement, self.parseStatement())) |statement| {
            return .{ .statement = statement };
        }

        if (try optional(Block, self.parseBlock())) |block| {
            return .{ .block = block };
        }

        return error.invalidInput;
    }

    fn parseStatement(self: *Self) !Statement {
        try self.enter();
        errdefer self.rollback();

        const identifier = try self.consume(.ident);
        _ = try self.consume(.equal);
        const expression = try self.parseExpression();
        _ = try self.consume(.semicolon);

        return .{
            .identifier = try self.allocator.dupe(u8, identifier.source),
            .expression = expression,
        };
    }

    fn parseExpressions(self: *Self) ![]Expression {
        try self.enter();
        errdefer self.rollback();

        var expressions = std.ArrayListUnmanaged(Expression).empty;
        while (try optional(Expression, self.parseExpression())) |expression| {
            try expressions.append(self.allocator, expression);
        }

        return expressions.toOwnedSlice(self.allocator);
    }

    fn parseExpression(self: *Self) !Expression {
        try self.enter();
        errdefer self.rollback();

        if (try optional(Atom, self.parseAtom())) |atom| {
            return .{ .atom = atom };
        }

        if (try optional([]Expression, self.parseListExpression())) |list| {
            return .{ .list = list };
        }

        return error.invalidInput;
    }

    fn parseAtom(self: *Self) !Atom {
        try self.enter();
        errdefer self.rollback();

        const token = try self.oneOf(&.{ .string, .ident, .number });
        return switch (token.token_type) {
            .string => .{ .string = try self.allocator.dupe(u8, token.source[1 .. token.source.len - 1]) },
            .ident => .{ .identifier = try self.allocator.dupe(u8, token.source) },
            .number => .{ .number = try self.allocator.dupe(u8, token.source) },
        };
    }

    fn parseListExpression(self: *Self) ![]Expression {
        try self.enter();
        errdefer self.rollback();

        _ = try self.consume(.left_paren);

        const expressions = try self.parseExpressions();
        _ = try self.consume(.right_paren);

        return expressions;
    }

    fn parseBlock(self: *Self) !Block {
        try self.enter();
        errdefer self.rollback();

        const list = try self.parseExpressions();
        _ = try self.consume(.left_brace);
        const items = try self.parseItems();
        _ = try self.consume(.right_brace);

        return .{
            .identifier = list,
            .items = items,
        };
    }
};
