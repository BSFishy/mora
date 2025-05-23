const std = @import("std");

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
};

pub const ListExpression = []Expression;

pub const Atom = union(enum) {
    string: []const u8,
    identifier: []const u8,
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
