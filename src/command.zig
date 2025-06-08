const std = @import("std");

fn padOutput(len: usize) void {
    for (0..len) |_| {
        std.debug.print(" ", .{});
    }
}

const FlagType = enum { flag, argument };
const Flag = struct {
    const Self = @This();

    name: []const u8,
    short: ?u8,
    long: ?[]const u8,
    help: ?[]const u8,
    flag_type: FlagType = .flag,

    pub fn fromStruct(comptime opt: anytype) !Flag {
        const opt_type = @typeInfo(@TypeOf(opt));
        const struct_type = switch (opt_type) {
            .@"struct" => |struct_type| struct_type,
            else => return error.notStruct,
        };

        if (struct_type.is_tuple) {
            return error.isTuple;
        }

        var flag: Flag = .{
            .name = undefined,
            .short = null,
            .long = null,
            .help = null,
        };

        for (struct_type.fields) |field| {
            @field(flag, field.name) = @field(opt, field.name);
        }

        if (flag.short == null and flag.long == null) {
            return error.noName;
        }

        return flag;
    }

    pub fn helpNameLen(self: *const Self) usize {
        var len: usize = 0;
        if (self.short != null) {
            len += 2;
        }

        if (self.long) |long| {
            len += 2 + long.len;
        }

        if (self.short != null and self.long != null) {
            len += 2;
        }

        if (self.flag_type == .argument) {
            len += 8;
        }

        return len;
    }

    pub fn printHelpName(self: *const Self) void {
        if (self.short) |short| {
            std.debug.print("-{c}", .{short});
        }

        if (self.short != null and self.long != null) {
            std.debug.print(", ", .{});
        }

        if (self.long) |long| {
            std.debug.print("--{s}", .{long});
        }

        if (self.flag_type == .argument) {
            std.debug.print(" <value>", .{});
        }
    }
};

const CommandOpts = struct {
    const Self = @This();

    name: []const u8,
    flags: []const Flag,
    subcommands: []const CommandOpts,
    rest: bool = false,
    handler: *const fn (allocator: std.mem.Allocator, args: *Args) anyerror!void,

    pub fn fromOpts(comptime opts: anytype) !Self {
        const opts_type = @typeInfo(@TypeOf(opts));
        const struct_type = switch (opts_type) {
            .@"struct" => |struct_type| struct_type,
            else => return error.notStruct,
        };

        if (struct_type.is_tuple) {
            return error.isTuple;
        }

        var command_opts: CommandOpts = .{
            .name = undefined,
            .flags = &.{},
            .subcommands = &.{},
            .handler = undefined,
        };

        for (struct_type.fields) |field| {
            if (std.mem.eql(u8, field.name, "flags")) {
                const flags_field = @field(opts, field.name);
                const flags_type = @typeInfo(@TypeOf(flags_field));
                const flags_struct = switch (flags_type) {
                    .@"struct" => |flags_struct| flags_struct,
                    else => return error.notStruct,
                };

                if (flags_struct.is_tuple) {
                    return error.isTuple;
                }

                var flags: [flags_struct.fields.len]Flag = undefined;
                for (flags_struct.fields, 0..) |flag_field, i| {
                    var flag = try Flag.fromStruct(@field(flags_field, flag_field.name));
                    flag.name = flag_field.name;
                    flags[i] = flag;
                }

                const const_flags = flags;
                command_opts.flags = &const_flags;
            } else if (std.mem.eql(u8, field.name, "subcommands")) {
                const subcommands = @field(opts, field.name);
                var subcommand_opts: [subcommands.len]CommandOpts = undefined;
                for (subcommands, 0..) |subcommand, i| {
                    subcommand_opts[i] = subcommand.command_opts;
                }

                const const_subcommand_opts = subcommand_opts;
                command_opts.subcommands = &const_subcommand_opts;
            } else {
                @field(command_opts, field.name) = @field(opts, field.name);
            }
        }

        return command_opts;
    }

    pub fn help(self: *const Self, subcommands: []const CommandOpts) !void {
        std.debug.print("Usage:\n ", .{});
        for (subcommands) |command| {
            std.debug.print(" {s}", .{command.name});
        }

        if (self.flags.len > 0) {
            std.debug.print(" [options]", .{});
        }

        if (self.subcommands.len > 0) {
            std.debug.print(" [subcommand]", .{});
        }

        if (self.rest) {
            std.debug.print(" [rest...]", .{});
        }

        std.debug.print("\n", .{});

        const flagLen = blk: {
            var max: ?usize = null;
            for (subcommands) |command| {
                for (command.flags) |flag| {
                    const len = flag.helpNameLen();
                    if (max) |m| {
                        if (len > m) {
                            max = len;
                        }
                    } else {
                        max = len;
                    }
                }
            }

            break :blk max;
        };

        if (flagLen) |len| {
            std.debug.print("\nOptions:\n", .{});

            for (subcommands) |command| {
                command.flagHelp(len);
            }
        }

        if (self.subcommands.len > 0) {
            std.debug.print("\nCommands:\n", .{});

            for (self.subcommands) |command| {
                std.debug.print("  {s}\n", .{command.name});
            }
        }
    }

    fn flagHelp(self: *const Self, len: usize) void {
        for (self.flags) |flag| {
            std.debug.print("  ", .{});
            flag.printHelpName();
            padOutput(len - flag.helpNameLen());

            if (flag.help) |help_text| {
                std.debug.print("  {s}", .{help_text});
            }

            std.debug.print("\n", .{});
        }
    }
};

const RuntimeFlag = struct {
    name: []const u8,
    value: ?[]const u8,
};

pub const Args = struct {
    const Builder = struct {
        flags: std.ArrayListUnmanaged([]const u8) = .empty,
        options: std.StringHashMapUnmanaged([]const u8) = .empty,
        rest: std.ArrayListUnmanaged([]const u8) = .empty,

        fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
            self.flags.deinit(allocator);
            self.options.deinit(allocator);
            self.rest.deinit(allocator);
        }

        fn build(self: *Builder, allocator: std.mem.Allocator) !Args {
            return .{
                .flags = try self.flags.toOwnedSlice(allocator),
                .options = self.options,
                .rest = try self.rest.toOwnedSlice(allocator),
            };
        }
    };

    flags: []const []const u8,
    options: std.StringHashMapUnmanaged([]const u8),
    rest: []const []const u8,

    fn builder() Builder {
        return .{};
    }

    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        allocator.free(self.flags);
        self.options.deinit(allocator);
        allocator.free(self.rest);
    }

    pub fn flag(self: *const Args, name: []const u8) bool {
        for (self.flags) |flag_name| {
            if (std.mem.eql(u8, name, flag_name)) {
                return true;
            }
        }

        return false;
    }

    pub fn option(self: *const Args, name: []const u8) ?[]const u8 {
        return self.options.get(name);
    }
};

pub fn Command(comptime opts: anytype) type {
    return struct {
        const Self = @This();

        const command_opts = CommandOpts.fromOpts(opts) catch |err| @compileError(std.fmt.comptimePrint("failed to compile command options: {any}", .{err}));

        pub fn parse(allocator: std.mem.Allocator) !void {
            const Subcommand = struct {
                subcommand: CommandOpts,
                index: usize,
            };

            var argIter = try std.process.argsWithAllocator(allocator);
            defer argIter.deinit();

            var subcommands = std.ArrayListUnmanaged(Subcommand).empty;
            defer subcommands.deinit(allocator);

            var subcommand = command_opts;
            try subcommands.append(allocator, .{ .subcommand = subcommand, .index = 0 });

            var i: usize = 0;
            while (argIter.next()) |arg| : (i += 1) {
                if (std.mem.eql(u8, arg, "--")) {
                    break;
                }

                for (subcommand.subcommands) |command| {
                    if (std.mem.eql(u8, command.name, arg)) {
                        try subcommands.append(allocator, .{ .subcommand = command, .index = i });
                        subcommand = command;
                    }
                }
            }

            argIter = try std.process.argsWithAllocator(allocator);
            defer argIter.deinit();

            var flags = std.ArrayListUnmanaged(RuntimeFlag).empty;
            defer flags.deinit(allocator);

            // discard command name
            _ = argIter.next();

            var builder = Args.builder();
            errdefer builder.deinit(allocator);

            i = 1;
            outer: while (argIter.next()) |arg| : (i += 1) {
                for (subcommands.items) |command| {
                    if (command.index == i) {
                        continue :outer;
                    }
                }

                if (std.mem.startsWith(u8, arg, "--")) {
                    // long flag or option
                    const eql_idx = std.mem.indexOf(u8, arg, "=");
                    const name = if (eql_idx) |idx| arg[2..idx] else arg[2..];

                    if (name.len == 0) {
                        if (!subcommand.rest) {
                            std.debug.print("invalid argument: {s}\n", .{arg});
                            return error.invalidInput;
                        }

                        while (argIter.next()) |next_arg| {
                            try builder.rest.append(allocator, next_arg);
                        }

                        break :outer;
                    }

                    var idx: usize = subcommands.items.len;
                    while (idx > 0) {
                        idx -= 1;
                        const command = subcommands.items[idx];
                        for (command.subcommand.flags) |flag| {
                            const long = flag.long orelse continue;

                            if (!std.mem.eql(u8, name, long)) {
                                continue;
                            }

                            if (flag.flag_type == .argument) {
                                const value = if (eql_idx) |eql|
                                    arg[eql + 1 ..]
                                else blk: {
                                    for (subcommands.items) |sub| {
                                        if (sub.index == i + 1) {
                                            std.debug.print("invalid argument: {s}\n", .{arg});
                                            return error.invalidInput;
                                        }
                                    }

                                    break :blk argIter.next() orelse {
                                        std.debug.print("invalid argument: {s}\n", .{arg});
                                        return error.invalidInput;
                                    };
                                };

                                try builder.options.put(allocator, flag.name, value);
                            } else {
                                try builder.flags.append(allocator, flag.name);
                            }

                            continue :outer;
                        }
                    }

                    std.debug.print("invalid argument: {s}\n", .{arg});
                    return error.invalidInput;
                } else if (std.mem.startsWith(u8, arg, "-")) {
                    // short flag or option
                    const name = if (arg.len > 1) arg[1] else {
                        std.debug.print("invalid input: {s}\n", .{arg});
                        return error.invalidInput;
                    };

                    if (arg.len > 2 and arg[2] != '=') {
                        std.debug.print("invalid input: {s}\n", .{arg});
                        return error.invalidInput;
                    }

                    var idx: usize = subcommands.items.len;
                    while (idx > 0) {
                        idx -= 1;
                        const command = subcommands.items[idx];
                        for (command.subcommand.flags) |flag| {
                            const short = flag.short orelse continue;

                            if (name != short) {
                                continue;
                            }

                            if (flag.flag_type == .argument) {
                                const value = if (arg.len > 2)
                                    arg[3..]
                                else blk: {
                                    for (subcommands.items) |sub| {
                                        if (sub.index == i + 1) {
                                            std.debug.print("invalid argument: {s}\n", .{arg});
                                            return error.invalidInput;
                                        }
                                    }

                                    break :blk argIter.next() orelse {
                                        std.debug.print("invalid argument: {s}\n", .{arg});
                                        return error.invalidInput;
                                    };
                                };

                                try builder.options.put(allocator, flag.name, value);
                            } else {
                                try builder.flags.append(allocator, flag.name);
                            }

                            continue :outer;
                        }
                    }

                    std.debug.print("invalid argument: {s}\n", .{arg});
                    return error.invalidInput;
                } else {
                    // positional or rest of input
                    if (!subcommand.rest) {
                        std.debug.print("invalid argument: {s}\n", .{arg});
                        return error.invalidInput;
                    }

                    try builder.rest.append(allocator, arg);
                    while (argIter.next()) |next_arg| {
                        try builder.rest.append(allocator, next_arg);
                    }

                    break :outer;
                }
            }

            var args = try builder.build(allocator);
            if (args.flag("help")) {
                defer args.deinit(allocator);

                var useful_subcommands = std.ArrayListUnmanaged(CommandOpts).empty;
                defer useful_subcommands.deinit(allocator);

                for (subcommands.items) |command| {
                    try useful_subcommands.append(allocator, command.subcommand);
                }

                try subcommand.help(useful_subcommands.items);
                return;
            }

            try subcommand.handler(allocator, &args);
        }
    };
}
