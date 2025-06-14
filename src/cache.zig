const std = @import("std");

const Self = @This();

dir: std.fs.Dir,

pub fn init() !Self {
    const cwd = std.fs.cwd();

    cwd.makeDir(".mora-cache") catch {};
    const dir = try cwd.openDir(".mora-cache", .{});

    return .{
        .dir = dir,
    };
}

pub fn deinit(self: *Self) void {
    self.dir.close();
}

pub const ModuleCache = struct {
    const ModuleCacheInner = struct {
        const ImageHash = struct {
            identifier: []const u8,
            hash: []const u8,
            image: []const u8,
        };

        customImageHashes: []ImageHash,
    };

    const CachedImageHash = struct {
        hash: []const u8,
        tag: []const u8,
    };

    file: std.fs.File,
    inner: ModuleCacheInner,

    pub fn deinit(self: *ModuleCache) void {
        self.file.close();
    }

    pub fn write(self: *const ModuleCache) !void {
        try self.file.seekTo(0);
        try self.file.setEndPos(0);

        try std.json.stringify(self.inner, .{}, self.file.writer());
    }

    pub fn getImageHash(self: *const ModuleCache, identifier: []const u8) ?CachedImageHash {
        for (self.inner.customImageHashes) |hash| {
            if (std.mem.eql(u8, hash.identifier, identifier)) {
                return .{
                    .hash = hash.hash,
                    .tag = hash.image,
                };
            }
        }

        return null;
    }

    pub fn setImageHash(self: *ModuleCache, allocator: std.mem.Allocator, identifier: []const u8, hash: []const u8, tag: []const u8) !void {
        var found = false;
        for (self.inner.customImageHashes) |*image| {
            if (std.mem.eql(u8, image.identifier, identifier)) {
                found = true;
                image.hash = hash;
                image.image = tag;
            }
        }

        if (found) {
            return;
        }

        var hashes = std.ArrayListUnmanaged(ModuleCacheInner.ImageHash).fromOwnedSlice(self.inner.customImageHashes);
        errdefer hashes.deinit(allocator);

        try hashes.append(allocator, .{
            .identifier = try allocator.dupe(u8, identifier),
            .hash = try allocator.dupe(u8, hash),
            .image = try allocator.dupe(u8, tag),
        });

        self.inner.customImageHashes = try hashes.toOwnedSlice(allocator);
    }
};

pub fn module(self: *const Self, allocator: std.mem.Allocator, name: []const u8) !ModuleCache {
    const filename = try std.fmt.allocPrint(allocator, "{s}.json", .{name});
    defer allocator.free(filename);

    const file = self.dir.openFile(filename, .{ .mode = .read_write }) catch try self.dir.createFile(filename, .{ .read = true });
    errdefer file.close();

    const contents = try file.readToEndAlloc(allocator, 2 * 1024 * 1024);
    defer allocator.free(contents);

    if (contents.len == 0) {
        return .{
            .file = file,
            .inner = .{
                .customImageHashes = try allocator.alloc(ModuleCache.ModuleCacheInner.ImageHash, 0),
            },
        };
    }

    const result = try std.json.parseFromSlice(ModuleCache.ModuleCacheInner, allocator, contents, .{ .allocate = .alloc_always });
    return .{
        .file = file,
        .inner = result.value,
    };
}
