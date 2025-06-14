const std = @import("std");

pub fn hashDir(allocator: std.mem.Allocator, d: std.fs.Dir) ![]const u8 {
    var dir = try d.openDir(".", .{ .iterate = true });
    defer dir.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            var subdir = try dir.openDir(entry.name, .{});
            defer subdir.close();

            hasher.update(try hashDir(allocator, subdir));
            continue;
        }

        if (entry.kind != .file) continue;

        const file_path = try dir.realpathAlloc(allocator, entry.name);
        defer allocator.free(file_path);

        const file = try dir.openFile(entry.name, .{});
        defer file.close();

        hasher.update(file_path);

        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = try file.read(&buffer);
            if (n == 0) break;
            hasher.update(buffer[0..n]);
        }
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    return try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&digest)});
}
