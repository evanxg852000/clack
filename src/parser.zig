const std = @import("std");
const value = @import("./value.zig");
const utils = @import("./utils.zig");

const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Value = value.Value;
pub const ValueType = value.ValueType;
pub const ValueError = value.ValueError;
pub const print = utils.print;
pub const println = utils.println;

pub const CliError = error{
    AppNameMissmatch,
    parserError,
    NotEnoughInput,
    UnexpectedCommand,
    UnknownArgument,
    ExpectedArgumentValue,
    RequiredArgument,
    ParseArgumentValueError,
    HandlerError,
} || std.mem.Allocator.Error;

pub const ErrorHandlerFn = *const fn (err: anyerror, err_msg: []const u8) anyerror;
pub const CommandHandlerFn = *const fn (*StringHashMap(Value)) anyerror!void;

pub const Argument = struct {
    const Self = @This();

    long: []const u8,
    atype: std.meta.Tag(Value),
    description: ?[]const u8,
    short: ?[]const u8,
    default_value: ?Value,
    required: bool,

    pub fn init(long: []const u8, atype: ValueType) Self {
        return Self{
            .long = long,
            .atype = atype,
            .short = null,
            .description = null,
            .default_value = null,
            .required = false,
        };
    }

    pub fn setShort(self: Self, short: []const u8) Self {
        return Self{
            .long = self.long,
            .atype = self.atype,
            .short = short,
            .description = self.description,
            .default_value = self.default_value,
            .required = self.required,
        };
    }

    pub fn setDefault(self: Self, default_value: Value) Self {
        std.debug.assert(self.atype == std.meta.activeTag(default_value));
        return Self{
            .long = self.long,
            .atype = self.atype,
            .short = self.short,
            .description = self.description,
            .default_value = default_value,
            .required = self.required,
        };
    }

    pub fn setDescription(self: Self, desc: []const u8) Self {
        return Self{
            .long = self.long,
            .atype = self.atype,
            .short = self.short,
            .description = desc,
            .default_value = self.default_value,
            .required = self.required,
        };
    }

    pub fn setRequired(self: Self) Self {
        return Self{
            .long = self.long,
            .atype = self.atype,
            .short = self.short,
            .description = self.description,
            .default_value = self.default_value,
            .required = true,
        };
    }
};

pub const Flag = struct {
    const Self = @This();

    inner: Argument,

    pub fn init(long: []const u8) Self {
        return Self{
            .inner = Argument.init(long, .boolean)
                .setDefault(Value{ .boolean = false }),
        };
    }

    pub fn setShort(self: Self, short: []const u8) Self {
        return Self{
            .inner = self.inner.setShort(short),
        };
    }

    pub fn setDescription(self: Self, desc: []const u8) Self {
        return Self{
            .inner = self.inner.setDescription(desc),
        };
    }

    pub fn getArgument(self: Self) Argument {
        return self.inner;
    }
};

pub const Command = struct {
    const Self = @This();

    name: []const u8,
    description: ?[]const u8,
    commands: StringHashMap(Self),
    arguments: ArrayList(Argument),
    handler: ?CommandHandlerFn,
    allocator: Allocator,
    build_error: ?anyerror,

    pub fn init(allocator: Allocator, name: []const u8) Self {
        return Self{
            .name = name,
            .description = null,
            .commands = StringHashMap(Self).init(allocator),
            .arguments = ArrayList(Argument).init(allocator),
            .handler = null,
            .allocator = allocator,
            .build_error = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.commands.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.commands.deinit();
        self.arguments.deinit();
    }

    pub fn setDescription(self: Self, desc: []const u8) Self {
        if (self.build_error) |_| return self;
        return Self{
            .name = self.name,
            .description = desc,
            .commands = self.commands,
            .arguments = self.arguments,
            .handler = self.handler,
            .allocator = self.allocator,
            .build_error = self.build_error,
        };
    }

    pub fn setHandler(self: Self, handler: CommandHandlerFn) Self {
        if (self.build_error) |_| return self;
        return Self{
            .name = self.name,
            .description = self.description,
            .commands = self.commands,
            .arguments = self.arguments,
            .handler = handler,
            .allocator = self.allocator,
            .build_error = self.build_error,
        };
    }

    pub fn addArgument(self: Self, arg: Argument) Self {
        if (self.build_error) |_| return self;

        var build_error: ?anyerror = null;
        var arguments = self.arguments;
        arguments.append(arg) catch |err| {
            build_error = err;
        };

        return Self{
            .name = self.name,
            .description = self.description,
            .commands = self.commands,
            .arguments = arguments,
            .handler = self.handler,
            .allocator = self.allocator,
            .build_error = build_error,
        };
    }

    pub fn addFlag(self: Self, flag: Flag) Self {
        if (self.build_error) |_| return self;

        var build_error: ?anyerror = null;
        var arguments = self.arguments;
        arguments.append(flag.getArgument()) catch |err| {
            build_error = err;
        };

        return Self{
            .name = self.name,
            .description = self.description,
            .commands = self.commands,
            .arguments = arguments,
            .handler = self.handler,
            .allocator = self.allocator,
            .build_error = build_error,
        };
    }

    pub fn addCommand(self: Self, command: Command) Self {
        if (self.build_error) |_| return self;

        var build_error: ?anyerror = null;
        var commands = self.commands;
        commands.put(command.name, command) catch |err| {
            build_error = err;
        };

        return Self{
            .name = self.name,
            .description = self.description,
            .commands = commands,
            .arguments = self.arguments,
            .handler = self.handler,
            .allocator = self.allocator,
            .build_error = build_error,
        };
    }

    pub fn build(self: Self) !Self {
        if (self.build_error) |err| {
            return err;
        }
        return self;
    }

    pub fn parse(self: *Self, args: [][] const u8, error_writer: anytype) !void {
        if (args.len == 0 and self.requiredArgumentCount() != 0) {
            try error_writer.print("Error: not enough arguments for command: `{s}`.\n", .{self.name});
            try self.usage(error_writer);
            return CliError.NotEnoughInput;
        }

        if(args.len > 0) {
            const command_name = args[0];
            const isSubcommand = !std.mem.startsWith(u8, command_name, "-");
            if (isSubcommand) {
                if (std.mem.eql(u8, command_name, "help")) {
                    return self.handleHelp();
                }
                var command = self.commands.get(command_name) orelse {
                    try error_writer.print("Error: unexpected command: `{s}`.\n", .{command_name});
                    try self.usage(error_writer);
                    return CliError.UnexpectedCommand;
                };
                return try command.parse(args[1..], error_writer);
            }
        }

        var params = StringHashMap(Value).init(self.allocator);
        defer params.deinit();
        const argument_count = args.len;
        var i: usize = 0;
        while (i < argument_count) : (i += 1) {
            const current_arg = args[i];
            const argument_search_key = if (std.mem.startsWith(u8, current_arg, "--"))
                current_arg[2..] // search using long-arg
            else
                current_arg[1..] // search using short-arg
                ;

            // find the arg & check if its a flag
            const argument = Self.find(self.arguments.items, argument_search_key) orelse {
                try error_writer.print("Error: unknown argument `{s}` for command: `{s}`.\n", .{ current_arg, self.name });
                try self.usage(error_writer);
                return CliError.UnknownArgument;
            };

            // Are we dealing with a flag?
            if (argument.atype == .boolean and argument.default_value != null) {
                try params.put(argument.long, Value{ .boolean = !argument.default_value.?.boolean });
                continue;
            }

            // We are dealing with argument, then capture the next item as value
            if (i + 1 >= argument_count) {
                try error_writer.print("Error: expected value for argument: `{s}`.\n", .{current_arg});
                try self.usage(error_writer);
                return CliError.ExpectedArgumentValue;
            }

            i += 1;
            const argument_value = Value.parseValue(argument.atype, args[i]) catch {
                try error_writer.print("Error: parsing value for argument: `{s}`.\n", .{current_arg});
                try self.usage(error_writer);
                return CliError.ParseArgumentValueError;
            };
            try params.put(argument.long, argument_value);
        }

        for (self.arguments.items) |argument| {
            // Verify required arguments are specified.
            if ((argument.required == true) and (params.get(argument.long) == null)) {
                try error_writer.print("Error: required argument: `{s}`.\n", .{argument.long});
                try self.usage(error_writer);
                return CliError.RequiredArgument;
            }

            // Add non-specified arguments with default value to params
            if ((params.get(argument.long) == null) and (argument.default_value != null)) {
                try params.put(argument.long, argument.default_value.?);
            }
        }

        if (self.handler) |handler_fn| {
            try handler_fn(&params);
        }
    }

    fn usage(self: Self, writer: anytype) CliError!void {
        if (self.commands.count() != 0) {
            if (self.description) |description| {
                try writer.print("{s}\n\n", .{description});
            }

            try writer.print("Usage: {s} [SUBCOMMAND] [OPTIONS]\n\n", .{self.name});

            try writer.print("Subcommands:\n", .{});
            var iter = self.commands.iterator();
            while (iter.next()) |entry| {
                const description = entry.value_ptr.description orelse "";
                try writer.print("- {s}: {s}\n", .{ entry.value_ptr.name, description });
            }
            try writer.print("- help: prints the command help message\n", .{});
            return;
        }

        try writer.print("Usage: {s} [SUBCOMMAND] [OPTIONS]\n\n", .{self.name});

        try writer.print("Subcommands:\n", .{});
        try writer.print("- help: prints the command help message\n\n", .{});

        try writer.print("Options:\n", .{});
        for (self.arguments.items) |argument| {
            const desc = argument.description orelse "";
            if (argument.short) |short| {
                try writer.print("-{s}, --{s}: {s}\n", .{ short, argument.long, desc });
            } else {
                try writer.print("  , --{s}: {s}\n", .{ argument.long, desc });
            }
        }
    }

    fn requiredArgumentCount(self: Self) usize {
        var count: usize  = 0;
        for (self.arguments.items) |argument| {
            if (argument.required) {
                count += 1;
            }
        }
        return count;
    }

    fn handleHelp(self: Self) CliError!void {
        var message_buffer = ArrayList(u8).init(self.allocator);
        defer message_buffer.deinit();
        try self.usage(message_buffer.writer());
        utils.print("{s}", .{message_buffer.items});
    }

    fn find(items: []Argument, argument_search_key: []const u8) ?*Argument {
        for (items) |*item| {
            if (std.mem.eql(u8, item.long, argument_search_key)) {
                return item;
            }

            if (item.short) |short| {
                if (std.mem.eql(u8, short, argument_search_key)) {
                    return item;
                }
            }
        }
        return null;
    }

};

pub const App = struct {
    const Self = @This();

    version: ?[]const u8,
    root: Command,
    error_handler: ErrorHandlerFn,
    allocator: Allocator,

    const DefaultErrorHandler = struct {
        fn handleError(err: anyerror, err_msg: []const u8) anyerror {
            std.debug.print("{s}", .{err_msg});
            return err;
        }
    };

    pub fn init(allocator: Allocator, name: []const u8) Self {
        return Self{
            .version = null,
            .root = Command.init(allocator, name),
            .error_handler = DefaultErrorHandler.handleError,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.root.deinit();
    }

    pub fn setVersion(self: Self, version: []const u8) Self {
        return Self{
            .version = version,
            .root = self.root,
            .error_handler = self.error_handler,
            .allocator = self.allocator,
        };
    }

    pub fn setErrorHandler(self: Self, error_handler: ErrorHandlerFn) Self {
        return Self{
            .version = self.version,
            .root = self.root,
            .error_handler = error_handler,
            .allocator = self.allocator,
        };
    }

    pub fn setDescription(self: Self, desc: []const u8) Self {
        return Self{
            .version = self.version,
            .root = self.root.setDescription(desc),
            .error_handler = self.error_handler,
            .allocator = self.allocator,
        };
    }

    pub fn addCommand(self: Self, command: Command) Self {
        return Self{
            .version = self.version,
            .root = self.root.addCommand(command),
            .error_handler = self.error_handler,
            .allocator = self.allocator,
        };
    }

    pub fn build(self: Self) !Self {
        return Self{
            .version = self.version,
            .root = try self.root.build(),
            .error_handler = self.error_handler,
            .allocator = self.allocator,
        };
    }

    pub fn run(self: *Self, args: [][] const u8) !void {
        var error_msg = ArrayList(u8).init(self.allocator);
        defer error_msg.deinit();
        const error_writer = error_msg.writer();

        if (args.len <= 1 ) {
            try error_writer.print("Error: no command specified: `{s}`.\n", .{self.root.name});
            try self.usage(error_writer);
            return self.error_handler(CliError.NotEnoughInput, error_msg.items);
        }
        
        if (!std.mem.endsWith(
            u8,
            args[0],
            self.root.name,
        )) {
            try error_writer.print("Error: app name doesn't match: `{s}`.\n", .{self.root.name});
            try self.usage(error_writer);
            return self.error_handler(CliError.AppNameMissmatch, error_msg.items);
        }

        self.root.parse(args[1..], error_writer) catch |err| {
            return self.error_handler(err, error_msg.items);
        };
    }

    pub fn usage(self: Self, writer: anytype) !void {
        return self.root.usage(writer);
    }
};

test "ArgumentConfig" {
    const arg1 = Argument.init("count", .integer);
    try testing.expectEqual(arg1.atype, .integer);
    try testing.expectEqualStrings(arg1.long, "count");
    try testing.expectEqual(arg1.short, null);
    try testing.expectEqual(arg1.default_value, null);

    const arg2 = Argument.init("name", .string)
        .setShort("n")
        .setDefault(try Value.parseValue(.string, "Jane"));
    try testing.expectEqual(arg2.atype, .string);
    try testing.expectEqualStrings(arg2.long, "name");
    try testing.expectEqualStrings(arg2.short.?, "n");
    try testing.expectEqual(arg2.default_value.?.string, "Jane");
}

test "FlagConfig" {
    const arg1 = Flag.init("enable").getArgument();
    try testing.expectEqual(arg1.atype, .boolean);
    try testing.expectEqualStrings(arg1.long, "enable");
    try testing.expectEqual(arg1.short, null);
    try testing.expectEqual(arg1.default_value.?.boolean, false);

    const arg2 = Flag.init("enable")
        .setShort("e")
        .getArgument();
    try testing.expectEqual(arg2.atype, .boolean);
    try testing.expectEqualStrings(arg2.long, "enable");
    try testing.expectEqualStrings(arg2.short.?, "e");
    try testing.expectEqual(arg2.default_value.?.boolean, false);
}

test "CommandConfig" {
    const allocator = testing.allocator;

    var cmd = try Command.init(allocator, "bada")
        .setDescription("bada-description")
        .addArgument(Argument.init("str", .string))
        .addArgument(Argument.init("int", .integer))
        .addArgument(Argument.init("float", .float))
        .addFlag(Flag.init("bool"))
        .addArgument(Argument.init("arr", .array))
        .addArgument(Argument.init("obj", .object))
        .build();
    defer cmd.deinit();

    try testing.expectEqualStrings(cmd.description.?, "bada-description");
    try testing.expectEqual(cmd.arguments.items.len, 6);
    try testing.expectEqual(cmd.commands.count(), 0);

    const arg = Command.find(cmd.arguments.items, "bool").?;
    try testing.expectEqual(arg.*, Argument{ .long = "bool", .atype = .boolean, .description = null, .short = null, .default_value = Value{ .boolean = false }, .required = false });

    cmd = cmd.addCommand(try Command.init(allocator, "bodo")
        .setDescription("bodo-description")
        .addArgument(Argument.init("str", .string))
        .build());
    try testing.expectEqual(cmd.commands.count(), 1);
}

fn build_app(allocator: std.mem.Allocator, cmd_handler_opt: ?CommandHandlerFn, err_handler_opt: ?ErrorHandlerFn) !App {
    const DummyAppHandler = struct {
        fn handle(params: *StringHashMap(Value)) anyerror!void {
            _ = params;
        }

        fn on_err(err: anyerror, err_msg: []const u8) anyerror {
            _ = err_msg;
            return err;
        }
    };
    const cmd_handler = cmd_handler_opt orelse DummyAppHandler.handle;
    const err_handler = err_handler_opt orelse DummyAppHandler.on_err;

    var app = try App
        .init(allocator, "test")
        .setDescription("app-test-desc")
        .setErrorHandler(err_handler)
        .addCommand(try Command.init(allocator, "foo")
            .setDescription("cmd-foo-desc")
            .addArgument(Argument.init("name", .string)
                .setDescription("arg-name-desc")
                .setShort("n")
                .setRequired()
            )
            .addFlag(Flag.init("enable")
                .setDescription("flag-enable-desc")
                .setShort("e")
            )
            .setHandler(cmd_handler)
            .build()
        )
        .addCommand(try Command.init(allocator, "bar")
            .setDescription("cmd-bar-desc")
            .addArgument(Argument.init("count", .integer)
                .setDescription("arg-count-desc")
                .setShort("c")
                .setDefault(Value{.integer = 12})
            )
            .setHandler(cmd_handler)
            .build()
        )
        .addCommand(try Command.init(allocator, "baz")
            .setDescription("cmd-baz-desc")
            .addArgument(Argument.init("count", .integer)
                .setDescription("arg-count-desc")
                .setShort("c")
            )
            .addArgument(Argument.init("size", .integer)
                .setDescription("arg-size-desc")
                .setRequired()
            )
            .setHandler(cmd_handler)
            .build()
        )
        .build();
    return app;
}

test "AppConfig" {
    //TODO: test attributes
}

test "AppConfigHandlerIsCalled" {
    const allocator = testing.allocator;

    const Handler = struct {
        var cmd_handled = false;
        fn handle(params: *StringHashMap(Value)) anyerror!void {
            cmd_handled = true;
            try testing.expectEqual(Value{.string = "jane"}, params.get("name").?);
            try testing.expectEqual(Value{.boolean = false}, params.get("enable").?);
        }
    };

    var app = try build_app(allocator, Handler.handle, null);
    defer app.deinit();
    var args = [_][]const u8{"test", "foo", "--name", "jane"};
    try app.run(&args);
    try testing.expect(Handler.cmd_handled);
}

test "AppConfigHandlerIsCalledWithShortcutArgument" {
    const allocator = testing.allocator;

    const Handler = struct {
        var cmd_handled = false;
        fn handle(params: *StringHashMap(Value)) anyerror!void {
            cmd_handled = true;
            try testing.expectEqual(Value{.string = "jane doe"}, params.get("name").?);
            try testing.expectEqual(Value{.boolean = true}, params.get("enable").?);
        }
    };

    var app = try build_app(allocator, Handler.handle, null);
    defer app.deinit();
    var args = [_][]const u8{"test", "foo", "-n", "jane doe", "-e"};
    try app.run(&args);
    try testing.expect(Handler.cmd_handled);
}

test "AppConfigHandlerDefaultArgumentIsAvailable" {
    const allocator = testing.allocator;

    const Handler = struct {
        var cmd_handled = false;
        fn handle(params: *StringHashMap(Value)) anyerror!void {
            cmd_handled = true;
            try testing.expectEqual(Value{.integer = 12}, params.get("count").?);
        }
    }; 

    var app = try build_app(allocator, Handler.handle, null);
    defer app.deinit();
    var args = [_][]const u8{"test", "bar"};
    try app.run(&args);
    try testing.expect(Handler.cmd_handled);
}

test "AppConfigHandlerDefaultArgumentIsOverridable" {
    const allocator = testing.allocator;

    const Handler = struct {
        var cmd_handled = false;
        fn handle(params: *StringHashMap(Value)) anyerror!void {
            cmd_handled = true;
            try testing.expectEqual(Value{.integer = 8}, params.get("count").?, );
        }
    }; 

    var app = try build_app(allocator, Handler.handle, null);
    defer app.deinit();
    var args = [_][]const u8{"test", "bar", "-c", "8"};
    try app.run(&args);
    try testing.expect(Handler.cmd_handled);
}

test "AppConfigErrorHandlerIsCalled" {
    const allocator = testing.allocator;

    const Handler = struct {
        var error_handled = false;
        fn handle(err: anyerror, err_msg: []const u8) anyerror {
            error_handled = true;
            _ = err_msg;
            return err;
        }
    };

    var app = try build_app(allocator, null, Handler.handle);
    defer app.deinit();
    var args = [_][]const u8{"test", "foo"};
    const result = app.run(&args);
    try testing.expect(Handler.error_handled);
    try testing.expectError(CliError.NotEnoughInput, result);
}

test "AppConfigErrorHandlerCheckError" {
    const allocator = testing.allocator;
    const TestCase = struct {
        [][]const u8, //args
        anyerror, // error
    };

    var cmd1 = [_][]const u8{"test", "foo"};
    var cmd2 = [_][]const u8{"test", "poop"};
    var cmd3 = [_][]const u8{"test", "foo", "--poop"};
    var cmd4 = [_][]const u8{"test", "foo", "--name"};
    var cmd5 = [_][]const u8{"test", "bar", "-c", "jane"};
    var cmd6 = [_][]const u8{"test", "baz", "-c", "12"};
    const tests = [_]TestCase{
        .{ &cmd1, CliError.NotEnoughInput},
        .{ &cmd2, CliError.UnexpectedCommand},
        .{ &cmd3, CliError.UnknownArgument},
        .{ &cmd4, CliError.ExpectedArgumentValue},
        .{ &cmd5, CliError.ParseArgumentValueError},
        .{ &cmd6, CliError.RequiredArgument},
    };

    for (tests) |testCase| { 
        const Handler = struct {
            fn handle(err: anyerror, err_msg: []const u8) anyerror {
                _ = err_msg;
                return err;
            }
        };
        var app = try build_app(allocator, null, Handler.handle);
        const result = app.run(@constCast(testCase[0]));
        try testing.expectError(testCase[1], result);
        app.deinit();


    }
}
