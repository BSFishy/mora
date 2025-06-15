const std = @import("std");
const parser = @import("parser.zig");
const Cache = @import("cache.zig");

const Self = @This();

const ModuleContext = struct {
    dir: std.fs.Dir,
    environment: []const u8,
    name: []const u8,
    cache: *Cache.ModuleCache,
};

const Config = struct {
    identifier: []const u8,
    name: parser.Expression,
    description: ?parser.Expression,

    pub fn fromBlock(allocator: std.mem.Allocator, block: parser.Block) !Config {
        if (block.identifier.len != 2) {
            return error.invalidConfigName;
        }

        const expression = block.identifier[1];
        const atom = expression.asAtom() orelse return error.invalidConfigName;
        const identifier = atom.asIdentifier() orelse return error.invalidConfigName;

        var name: ?parser.Expression = null;
        var description: ?parser.Expression = null;

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "name")) {
                        name = try dupeExpression(allocator, statement.expression);
                    } else if (std.mem.eql(u8, statement.identifier, "description")) {
                        description = try dupeExpression(allocator, statement.expression);
                    }
                },
                .block => return error.invalidBlock,
            }
        }

        return .{
            .identifier = try allocator.dupe(u8, identifier),
            .name = name orelse return error.invalidConfig,
            .description = description,
        };
    }
};

const Wingman = struct {
    image: parser.Expression,

    pub fn fromBlock(allocator: std.mem.Allocator, ctx: ModuleContext, evaluationContext: *const parser.EvaluationContext, block: parser.Block) !Wingman {
        _ = ctx;

        var image: ?parser.Expression = null;

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "image")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        image = try expr.eagerEvaluate(evaluationContext);
                    }
                },
                .block => return error.invalidBlock,
            }
        }

        return .{
            .image = image orelse return error.invalidWingman,
        };
    }
};

const Service = struct {
    name: []const u8,
    image: parser.Expression,
    requires: []parser.Expression,
    wingmen: []Wingman,

    pub fn fromBlock(allocator: std.mem.Allocator, ctx: ModuleContext, block: parser.Block) !Service {
        if (block.identifier.len != 2) {
            return error.invalidServiceName;
        }

        const expression = block.identifier[1];
        const atom = expression.asAtom() orelse return error.invalidServiceName;
        const name = atom.asIdentifier() orelse return error.invalidServiceName;

        const evaluationContext = parser.EvaluationContext{
            .allocator = allocator,
            .cache = ctx.cache,
            .environment = ctx.environment,
            .module = ctx.name,
            .service = name,
            .dir = ctx.dir,
        };

        var image: ?parser.Expression = null;
        var requires = std.ArrayListUnmanaged(parser.Expression).empty;
        errdefer requires.deinit(allocator);

        var wingmen = std.ArrayListUnmanaged(Wingman).empty;
        errdefer wingmen.deinit(allocator);

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "image")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        image = try expr.eagerEvaluate(&evaluationContext);
                    } else if (std.mem.eql(u8, statement.identifier, "requires")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        try requires.append(allocator, try expr.eagerEvaluate(&evaluationContext));
                    } else {
                        return error.invalidStatement;
                    }
                },
                .block => |blk| {
                    if (matchIdentifier(blk.identifier, "wingman")) {
                        try wingmen.append(allocator, try Wingman.fromBlock(allocator, ctx, &evaluationContext, blk));
                    } else {
                        return error.invalidBlock;
                    }
                },
            }
        }

        return .{
            .name = try allocator.dupe(u8, name),
            .image = image orelse return error.noImage,
            .requires = try requires.toOwnedSlice(allocator),
            .wingmen = try wingmen.toOwnedSlice(allocator),
        };
    }
};

dir: std.fs.Dir,
name: []const u8,
configs: []Config,
services: []Service,

fn dupeExpression(allocator: std.mem.Allocator, expression: parser.Expression) !parser.Expression {
    switch (expression) {
        .atom => |atom| {
            return .{ .atom = switch (atom) {
                .identifier => |identifier| .{ .identifier = try allocator.dupe(u8, identifier) },
                .string => |string| .{ .string = try allocator.dupe(u8, string) },
                .number => |number| .{ .number = try allocator.dupe(u8, number) },
            } };
        },
        .list => |list| {
            var newList = std.ArrayListUnmanaged(parser.Expression).empty;

            for (list) |item| {
                try newList.append(allocator, try dupeExpression(allocator, item));
            }

            return .{ .list = try newList.toOwnedSlice(allocator) };
        },
    }
}

fn matchIdentifier(haystack: []const parser.Expression, needle: []const u8) bool {
    if (haystack.len < 1) {
        return false;
    }

    const expression = haystack[0];
    const atom = expression.asAtom() orelse return false;
    const identifier = atom.asIdentifier() orelse return false;

    return std.mem.eql(u8, needle, identifier);
}

pub fn init(allocator: std.mem.Allocator, dir: std.fs.Dir, name: []const u8) !Self {
    var owned = try dir.openDir(".", .{});
    errdefer owned.close();

    return .{
        .dir = owned,
        .name = name,
        .configs = try allocator.alloc(Config, 0),
        .services = try allocator.alloc(Service, 0),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.dir.close();
    allocator.free(self.services);
}

pub fn insert(self: *Self, allocator: std.mem.Allocator, cache: *Cache.ModuleCache, environment: []const u8, items: []const parser.Item) !void {
    var configs = std.ArrayListUnmanaged(Config).fromOwnedSlice(self.configs);
    var services = std.ArrayListUnmanaged(Service).fromOwnedSlice(self.services);

    for (items) |item| {
        switch (item) {
            .statement => return error.invalidStatement,
            .block => |block| {
                if (matchIdentifier(block.identifier, "service")) {
                    try services.append(allocator, try Service.fromBlock(allocator, .{ .cache = cache, .dir = self.dir, .environment = environment, .name = self.name }, block));
                } else if (matchIdentifier(block.identifier, "config")) {
                    try configs.append(allocator, try Config.fromBlock(allocator, block));
                } else {
                    return error.invalidBlock;
                }
            },
        }
    }

    self.configs = try configs.toOwnedSlice(allocator);
    self.services = try services.toOwnedSlice(allocator);
}
