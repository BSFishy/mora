const std = @import("std");
const parser = @import("parser.zig");

const Self = @This();

const Service = struct {
    name: []const u8,
    image: parser.Expression,

    pub fn fromBlock(block: parser.Block) !Service {
        if (block.identifier.len != 2) {
            return error.invalidServiceName;
        }

        const expression = block.identifier[1];
        const atom = switch (expression) {
            .atom => |a| a,
            else => return error.invalidServiceName,
        };
        const name = switch (atom) {
            .identifier => |ident| ident,
            else => return error.invalidServiceName,
        };

        var image: ?parser.Expression = null;

        for (block.items) |item| {
            switch (item) {
                .statement => |statement| {
                    if (std.mem.eql(u8, statement.identifier, "image")) {
                        image = statement.expression;
                    } else {
                        return error.invalidStatement;
                    }
                },
                .block => return error.invalidBlock,
            }
        }

        return .{
            .name = name,
            .image = image orelse return error.noImage,
        };
    }
};

services: []Service,

fn matchIdentifier(haystack: []const parser.Expression, needle: []const u8) bool {
    if (haystack.len < 1) {
        return false;
    }

    const expression = haystack[0];
    const atom = switch (expression) {
        .atom => |a| a,
        else => return false,
    };
    const identifier = switch (atom) {
        .identifier => |ident| ident,
        else => return false,
    };

    return std.mem.eql(u8, needle, identifier);
}

pub fn init(allocator: std.mem.Allocator, items: []const parser.Item) !Self {
    var services = std.ArrayListUnmanaged(Service).empty;

    for (items) |item| {
        switch (item) {
            .statement => return error.invalidStatement,
            .block => |block| {
                if (matchIdentifier(block.identifier, "service")) {
                    try services.append(allocator, try Service.fromBlock(block));
                } else {
                    return error.invalidBlock;
                }
            },
        }
    }

    return .{
        .services = try services.toOwnedSlice(allocator),
    };
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    allocator.free(self.services);
}
