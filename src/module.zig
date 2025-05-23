const std = @import("std");
const parser = @import("parser.zig");

const Self = @This();

const Service = struct {
    name: []const u8,
    image: parser.Expression,

    pub fn fromBlock(allocator: std.mem.Allocator, block: parser.Block) !Service {
        if (block.identifier.len != 2) {
            return error.invalidServiceName;
        }

        const expression = block.identifier[1];
        const atom = expression.asAtom() orelse return error.invalidServiceName;
        const name = atom.asIdentifier() orelse return error.invalidServiceName;

        var image: ?parser.Expression = null;

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "image")) {
                        image = try dupeExpression(allocator, statement.expression);
                    } else {
                        return error.invalidStatement;
                    }
                },
                .block => return error.invalidBlock,
            }
        }

        return .{
            .name = try allocator.dupe(u8, name),
            .image = image orelse return error.noImage,
        };
    }
};

name: []const u8,
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

pub fn init(allocator: std.mem.Allocator, name: []const u8) !Self {
    return .{
        .name = name,
        .services = try allocator.alloc(Service, 0),
    };
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    allocator.free(self.services);
}

pub fn insert(self: *Self, allocator: std.mem.Allocator, items: []const parser.Item) !void {
    var services = std.ArrayListUnmanaged(Service).fromOwnedSlice(self.services);

    for (items) |item| {
        switch (item) {
            .statement => return error.invalidStatement,
            .block => |block| {
                if (matchIdentifier(block.identifier, "service")) {
                    try services.append(allocator, try Service.fromBlock(allocator, block));
                } else {
                    return error.invalidBlock;
                }
            },
        }
    }

    self.services = try services.toOwnedSlice(allocator);
}
