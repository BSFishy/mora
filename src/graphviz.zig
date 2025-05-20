const std = @import("std");
const parser = @import("parser.zig");

pub fn printGraphviz(items: []const parser.Item) void {
    var id_gen: usize = 0;

    std.debug.print("digraph AST {{\n", .{});
    for (items) |item| {
        _ = printItem(item, null, &id_gen);
    }
    std.debug.print("}}\n", .{});
}

fn printItem(item: parser.Item, parent: ?usize, id_gen: *usize) usize {
    const id = id_gen.*;
    id_gen.* += 1;

    const label = switch (item) {
        .statement => "Statement",
        .block => "Block",
    };
    std.debug.print("  n{d} [label=\"{s}\"];\n", .{ id, label });
    if (parent) |pid| {
        std.debug.print("  n{d} -> n{d};\n", .{ pid, id });
    }

    switch (item) {
        .statement => |stmt| {
            const expr_id = printExpression(stmt.expression, id, id_gen);
            const label_id = id_gen.*;
            id_gen.* += 1;
            std.debug.print("  n{d} [label=\"{s}\"];\n", .{ label_id, stmt.identifier });
            std.debug.print("  n{d} -> n{d};\n", .{ id, label_id });
            std.debug.print("  n{d} -> n{d};\n", .{ id, expr_id });
        },
        .block => |blk| {
            const list_id = id_gen.*;
            id_gen.* += 1;
            std.debug.print("  n{d} [label=\"ListExpression\"];\n", .{list_id});
            std.debug.print("  n{d} -> n{d};\n", .{ id, list_id });
            for (blk.identifier) |expr| {
                const sub_id = printExpression(expr, list_id, id_gen);
                std.debug.print("  n{d} -> n{d};\n", .{ list_id, sub_id });
            }

            for (blk.items) |sub_item| {
                _ = printItem(sub_item, id, id_gen);
            }
        },
    }

    return id;
}

fn printExpression(expr: parser.Expression, parent: usize, id_gen: *usize) usize {
    const id = id_gen.*;
    id_gen.* += 1;

    const label = switch (expr) {
        .atom => "Atom",
        .list => "List",
    };
    std.debug.print("  n{d} [label=\"{s}\"];\n", .{ id, label });
    std.debug.print("  n{d} -> n{d};\n", .{ parent, id });

    switch (expr) {
        .atom => |a| {
            const atom_label = switch (a) {
                .identifier => a.identifier,
                .string => a.string,
                .number => a.number,
            };
            const atom_id = id_gen.*;
            id_gen.* += 1;
            std.debug.print("  n{d} [label=\"{s}\"];\n", .{ atom_id, atom_label });
            std.debug.print("  n{d} -> n{d};\n", .{ id, atom_id });
        },
        .list => |lst| {
            for (lst) |sub_expr| {
                _ = printExpression(sub_expr, id, id_gen);
            }
        },
    }

    return id;
}
