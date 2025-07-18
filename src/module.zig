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

const Env = struct {
    name: []const u8,
    value: parser.Expression,

    pub fn fromBlock(allocator: std.mem.Allocator, ctx: *const parser.EvaluationContext, block: parser.Block) ![]Env {
        if (block.identifier.len != 1) {
            return error.invalidEnvBlock;
        }

        var envs = std.ArrayListUnmanaged(Env).empty;
        errdefer envs.deinit(allocator);

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    const expr = try dupeExpression(allocator, statement.expression);
                    try envs.append(allocator, .{
                        .name = try allocator.dupe(u8, statement.identifier),
                        .value = try expr.eagerEvaluate(ctx),
                    });
                },
                .block => return error.invalidBlock,
            }
        }

        return try envs.toOwnedSlice(allocator);
    }
};

const ConfigMap = struct {
    path: parser.Expression,
    file: parser.Expression,

    pub fn fromBlock(allocator: std.mem.Allocator, ctx: *const parser.EvaluationContext, block: parser.Block) !ConfigMap {
        if (block.identifier.len != 1) {
            return error.invalidEnvBlock;
        }

        var path: ?parser.Expression = null;
        var file: ?parser.Expression = null;

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "path")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        path = try expr.eagerEvaluate(ctx);
                    } else if (std.mem.eql(u8, statement.identifier, "file")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        file = try expr.eagerEvaluate(ctx);
                    } else {
                        return error.invalidConfigMap;
                    }
                },
                .block => return error.invalidBlock,
            }
        }

        return .{
            .path = path orelse return error.invalidConfigMap,
            .file = file orelse return error.invalidConfigMap,
        };
    }
};

const Service = struct {
    name: []const u8,
    image: parser.Expression,
    command: ?parser.Expression,
    requires: []parser.Expression,
    configs: []ConfigMap,
    wingman: ?Wingman,
    env: []Env,

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
        var command: ?parser.Expression = null;
        var wingman: ?Wingman = null;
        var requires = std.ArrayListUnmanaged(parser.Expression).empty;
        errdefer requires.deinit(allocator);

        var configs = std.ArrayListUnmanaged(ConfigMap).empty;
        errdefer configs.deinit(allocator);

        var envs = std.ArrayListUnmanaged(Env).empty;
        errdefer envs.deinit(allocator);

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "image")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        image = try expr.eagerEvaluate(&evaluationContext);
                    } else if (std.mem.eql(u8, statement.identifier, "requires")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        try requires.append(allocator, try expr.eagerEvaluate(&evaluationContext));
                    } else if (std.mem.eql(u8, statement.identifier, "command")) {
                        const expr = try dupeExpression(allocator, statement.expression);
                        command = try expr.eagerEvaluate(&evaluationContext);
                    } else {
                        return error.invalidStatement;
                    }
                },
                .block => |blk| {
                    if (matchIdentifier(blk.identifier, "wingman")) {
                        wingman = try Wingman.fromBlock(allocator, ctx, &evaluationContext, blk);
                    } else if (matchIdentifier(blk.identifier, "env")) {
                        try envs.appendSlice(allocator, try Env.fromBlock(allocator, &evaluationContext, blk));
                    } else if (matchIdentifier(blk.identifier, "config")) {
                        try configs.append(allocator, try ConfigMap.fromBlock(allocator, &evaluationContext, blk));
                    } else {
                        return error.invalidBlock;
                    }
                },
            }
        }

        return .{
            .name = try allocator.dupe(u8, name),
            .image = image orelse return error.noImage,
            .command = command,
            .requires = try requires.toOwnedSlice(allocator),
            .configs = try configs.toOwnedSlice(allocator),
            .wingman = wingman,
            .env = try envs.toOwnedSlice(allocator),
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
                .file => |file| .{ .file = try allocator.dupe(u8, file) },
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
