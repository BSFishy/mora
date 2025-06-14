const std = @import("std");
const Api = @import("api.zig");
const parser = @import("parser.zig");
const docker = @import("docker.zig");

pub fn image(ctx: *const parser.EvaluationContext, args: []const parser.Expression) !parser.ReturnValue {
    if (args.len != 1) {
        return error.invalidImageCall;
    }

    const arg = try args[0].evaluate(ctx);
    const sub_path = (arg orelse return error.invalidFunction).asString() orelse return error.invalidFunction;

    var dir = try ctx.dir.openDir(sub_path, .{});
    defer dir.close();

    const path = try dir.realpathAlloc(ctx.allocator, ".");
    defer ctx.allocator.free(path);

    const tag = try docker.build(ctx.allocator, ctx.module, path);

    const basename = std.fs.path.basename(path);
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

    return .{ .string = response.image };
}
