const std = @import("std");

const io = std.io;

var stdout_mutex = std.Thread.Mutex{};

pub fn print(comptime fmt: []const u8, args: anytype) void {
    stdout_mutex.lock();
    defer stdout_mutex.unlock();
    const stdout = io.getStdOut().writer();
    nosuspend stdout.print(fmt, args) catch return;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    stdout_mutex.lock();
    defer stdout_mutex.unlock();
    const stdout = io.getStdOut().writer();
    nosuspend stdout.print(fmt, args) catch return;
    nosuspend stdout.print("\n", .{}) catch return;
}
