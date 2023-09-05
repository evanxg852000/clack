const std = @import("std");

pub const parser = @import("./parser.zig");

pub const App = parser.App;
pub const Argument = parser.Argument;
pub const Flag = parser.Flag;

pub const CommandHandlerFn = parser.CommandHandlerFn;
pub const ErrorHandlerFn = parser.ErrorHandlerFn;
pub const CliError = parser.CliError;

pub const Value = parser.Value;
pub const ValueType = parser.ValueType;
pub const ValueError = parser.ValueError;

pub const print = parser.print;
pub const println = parser.println;

test {
    _ = @import("./parser.zig");
    _ = @import("./value.zig");
}
