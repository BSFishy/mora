const std = @import("std");
const hashDir = @import("hash.zig").hashDir;
const Api = @import("api.zig");
const parser = @import("parser.zig");
const docker = @import("docker.zig");

pub fn image(ctx: *const parser.EvaluationContext, args: []const parser.Expression) !parser.Expression {
    if (args.len != 1) {
        return error.invalidImageCall;
    }

    const arg = try args[0].eagerEvaluate(ctx);
    const arg_atom = arg.asAtom() orelse return error.invalidImageFunction;
    const sub_path = arg_atom.asString() orelse return error.invalidImageFunction;

    var dir = try ctx.dir.openDir(sub_path, .{});
    defer dir.close();

    const path = try dir.realpathAlloc(ctx.allocator, ".");
    defer ctx.allocator.free(path);

    const basename = std.fs.path.basename(path);

    const computedHash = try hashDir(ctx.allocator, dir);
    const previousHash = ctx.cache.getImageHash(basename);
    if (previousHash) |hash| {
        if (std.mem.eql(u8, computedHash, hash.hash)) {
            return .{ .atom = .{ .string = hash.tag } };
        }
    }

    const tag = try docker.build(ctx.allocator, ctx.module, path);

    const out = try std.fmt.allocPrint(ctx.allocator, "/tmp/mora-{s}-{s}-{s}.tar", .{ ctx.module, ctx.service, basename });
    defer ctx.allocator.free(out);

    try docker.save(ctx.allocator, tag, out);

    var api = try Api.fromConfig(ctx.allocator);
    defer api.deinit(ctx.allocator);

    const publishContext = Api.PublishContext{
        .allocator = ctx.allocator,
        .environment = ctx.environment,
        .module = ctx.module,
        .image = basename,
        .tarball = out,
    };
    const response = try api.publish(publishContext);

    try ctx.cache.setImageHash(ctx.allocator, basename, computedHash, response.image);

    return .{ .atom = .{ .string = response.image } };
}
