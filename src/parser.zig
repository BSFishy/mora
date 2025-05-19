const std = @import("std");

const lexer = @import("lexer.zig");

pub const Item = union(enum) {
    statement: Statement,
    block: Block,
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
};

pub const ListExpression = []Expression;

pub const Atom = union(enum) {
    string: []const u8,
    identifier: []const u8,
    number: []const u8,
};

pub fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) void {
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

    fn deinit(self: *const Self) void {
        self.stack.deinit(self.allocator);
    }

    pub fn parse(allocator: std.mem.Allocator, tokens: []lexer.Token) ![]Item {
        const self = Self.init(allocator, tokens);
        defer self.deinit();

        return try self.parseItems();
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
        errdefer {
            items.deinit(self.allocator);
        }

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

        return .{
            .identifier = try self.allocator.dupe(u8, identifier.source),
            .expression = expression,
        };
    }

    fn parseExpressions(self: *Self) ![]Expression {
        try self.enter();
        errdefer self.rollback();

        var expressions = std.ArrayListUnmanaged(Expression).empty;
        errdefer {
            expressions.deinit(self.allocator);
        }

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

        return error.unimplemented;
    }

    fn parseAtom(self: *Self) !Atom {
        try self.enter();
        errdefer self.rollback();

        return error.unimplemented;
    }

    fn parseListExpression(self: *Self) ![]Expression {
        try self.enter();
        errdefer self.rollback();

        _ = try self.consume(.left_paren);

        const expressions = try self.parseExpressions();
        errdefer self.allocator.free(expressions);

        _ = try self.consume(.right_paren);

        return expressions;
    }

    fn parseBlock(self: *Self) !Block {
        try self.enter();
        errdefer self.rollback();

        const list = try self.parseExpressions();
        errdefer self.allocator.free(list);

        _ = try self.consume(.left_brace);

        const items = try self.parseItems();
        errdefer self.allocator.free(items);

        _ = try self.consume(.right_brace);

        return .{
            .identifier = list,
            .items = items,
        };
    }
};
