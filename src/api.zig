const std = @import("std");
const Payload = @import("payload.zig");
const AuthConfig = @import("auth.zig").Config;

const Self = @This();

client: std.http.Client,
base_url: []const u8,
token: []const u8,

pub fn init(allocator: std.mem.Allocator, base_url: []const u8, token: []const u8) !Self {
    const client = std.http.Client{ .allocator = allocator };
    return .{
        .client = client,
        .base_url = try allocator.dupe(u8, base_url),
        .token = try allocator.dupe(u8, token),
    };
}

pub fn fromConfig(allocator: std.mem.Allocator) !Self {
    const data_dir = try std.fs.getAppDataDir(allocator, "mora");
    defer allocator.free(data_dir);

    var dir = try std.fs.openDirAbsolute(data_dir, .{});
    defer dir.close();

    // NOTE: max file size is 2 MiB. i should NEVER run over this, but just like
    // idk keep that in mind
    const configContents = try dir.readFileAlloc(allocator, "config.json", 2 * 1024 * 1024);
    defer allocator.free(configContents);

    const config = try std.json.parseFromSlice(AuthConfig, allocator, configContents, .{});
    defer config.deinit();

    const client = std.http.Client{ .allocator = allocator };
    return .{
        .client = client,
        .base_url = try allocator.dupe(u8, config.value.domain),
        .token = try allocator.dupe(u8, config.value.token),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.client.deinit();
    allocator.free(self.base_url);
    allocator.free(self.token);
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

pub fn deploy(self: *Self, allocator: std.mem.Allocator, env_slug: []const u8, config: Payload) !void {
    const url = try std.fmt.allocPrint(allocator, "{s}/api/v1/environment/{s}/deployment", .{ self.base_url, env_slug });
    defer allocator.free(url);

    const header_buffer = try allocator.alloc(u8, 2 * 1024);
    defer allocator.free(header_buffer);

    const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.token});
    defer allocator.free(authorization);

    const headers = std.http.Client.Request.Headers{ .authorization = .{ .override = authorization } };

    var request = try self.client.open(.POST, try std.Uri.parse(url), .{ .headers = headers, .server_header_buffer = header_buffer });
    defer request.deinit();

    request.transfer_encoding = .chunked;

    try request.send();

    const writer = request.writer();
    try std.json.stringify(config, .{}, writer);

    try request.finish();
    try request.wait();

    const response = request.response;
    if (response.status != std.http.Status.ok) {
        return error.failedRequest;
    }
}
