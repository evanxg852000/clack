# clack

A command line parser for Zig ⚡

⚠️ Warning: please, do not rely on this library for production work. 
It's still a work in progress (testing).


## demo

`$ ./demo foo --name jane`

```zig
const std = @import("std");
const clack = @import("clack");

const AppHandler = struct {
    pub fn fooHandler(params: *std.StringHashMap(clack.Value)) !void {
        const name = params.get("name").?;
        clack.println("Hello {s}", .{ name.string });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try clack.App
        .init(allocator, "demo")
        .setDescription("A simple command line app to demonstrate clack.")
        .addCommand(try clack.Command.init(allocator, "foo")
                .setDescription("a command to display name")
                .addArgument(clack.Argument.init("name", .string)
                    .setShort("n")
                    .setRequired()
                    .setDescription("specify the name")
                )
                .setHandler(AppHandler.fooHandler)
                .build()
            )
        .build();
    defer app.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    app.run(args) catch {};
}
```
