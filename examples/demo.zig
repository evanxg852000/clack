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
        .init(allocator, "main")
        .setDescription("description")
        .addCommand(try clack.Command.init(allocator, "foo")
                .setDescription("a command to display name")
                .addArgument(clack.Argument.init("name", .string)
                    .setShort("n")
                    .setDescription("specify the name")
                )
                .setHandler(AppHandler.fooHandler)
                .build()
            )
        .build();
    defer app.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    try app.run(args);
}
