const std = @import("std");
const Module = @import("module.zig");

const Self = @This();

modules: []const Module,
