const std = @import("std");

const Self = @This();

client: std.http.Client,
base_url: []const u8,
token: []const u8,

pub fn init(allocator: std.mem.Allocator, base_url: []const u8, token: []const u8) Self {
    const client = std.http.Client{ .allocator = allocator };
    return .{
        .client = client,
        .base_url = base_url,
        .token = token,
    };
}

pub fn deinit(self: *Self) void {
    self.client.deinit();
}

pub fn ping(self: *Self, allocator: std.mem.Allocator) !void {
    const url = try std.fmt.allocPrint(allocator, "{s}/api/v1/ping", .{self.base_url});
    defer allocator.free(url);

    const header_buffer = try allocator.alloc(u8, 2 * 1024);
    defer allocator.free(header_buffer);

    const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.token});
    defer allocator.free(authorization);

    const headers = std.http.Client.Request.Headers{ .authorization = .{ .override = authorization } };

    var request = try self.client.open(.GET, try std.Uri.parse(url), .{ .headers = headers, .server_header_buffer = header_buffer });
    defer request.deinit();

    try request.send();
    try request.wait();

    const response = request.response;
    if (response.status != std.http.Status.ok) {
        return error.failedRequest;
    }
}
