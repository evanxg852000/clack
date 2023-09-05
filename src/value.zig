const std = @import("std");

const mem = std.mem;
const ParseIntError = std.fmt.ParseIntError;
const ParseFloatError = std.fmt.ParseFloatError;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

pub const ValueError = error{
    ParseInterger,
    ParseFloat,
    ParseString,
    ParseBoolean,
    ParseArray,
    ParseObject,
} || ParseIntError || ParseFloatError;

pub const Value = union(enum) {
    const Self = @This();

    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    array: ArrayList(Value),
    object: StringHashMap(Value),

    /// Extracts integer value
    pub fn asInteger(self: Self) ?i64 {
        return switch (self) {
            .integer => |i| i,
            else => null,
        };
    }

    /// Extracts float value
    pub fn asFloat(self: Self) ?f64 {
        return switch (self) {
            .float => |f| f,
            else => null,
        };
    }

    /// Extracts string value
    pub fn asString(self: Self) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }

    /// Extracts string value
    pub fn asBoolean(self: Self) ?bool {
        return switch (self) {
            .boolean => |b| b,
            else => null,
        };
    }

    /// Only for array value.
    pub fn items(self: Self) ?[]Self {
        return switch (self) {
            .array => |list| list.items,
            else => null,
        };
    }

    /// Only for object value.
    pub fn get(self: Self, key: []const u8) ?Self {
        return switch (self) {
            .object => |map| map.get(key),
            else => null,
        };
    }

    pub fn parseValue(atype: ValueType, value_str: []const u8) ValueError!Self {
        return switch (atype) {
            .integer => Value{ .integer = try std.fmt.parseInt(i64, value_str, 10) },
            .float => Value{ .float = try std.fmt.parseFloat(f64, value_str) },
            .string => Value{ .string = value_str },
            .boolean => Self.parseBoolean(value_str),
            .array => ValueError.ParseArray, //TODO: Support parsing arrays
            .object => ValueError.ParseObject, //TODO: Support parsing objects
        };
    }

    fn parseBoolean(str: []const u8) ValueError!Value {
        if (mem.eql(u8, str, "true")) {
            return Value{ .boolean = true };
        }
        if (mem.eql(u8, str, "false")) {
            return Value{ .boolean = false };
        }
        return ValueError.ParseBoolean;
    }
};

pub const ValueType = std.meta.Tag(Value);
