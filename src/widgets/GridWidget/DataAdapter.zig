//! DataAdapters provide ....
//! All DataAdapters must implement
//! - pub fn value(row_num: usize) T
//! - pub fn setValue(row_num: usize, val: T) void
//! - pub fn len() usize
//!

const std = @import("std");

/// This DataAdapter demonstrates the interface.
/// It is not intended to be used.
const DataAdapter = @This();
pub fn value(self: *DataAdapter, row_num: usize) void {
    _ = self;
    _ = row_num;
}

pub fn setValue(self: *DataAdapter, row_num: usize, val: void) void {
    _ = self;
    _ = row_num;
    _ = val;
}

pub fn len(self: *DataAdapter) usize {
    _ = self;
    return 0;
}

pub fn Slice(T: type) type {
    return struct {
        const Self = @This();
        slice: []T,

        pub fn value(self: Self, row: usize) T {
            return self.slice[row];
        }

        pub fn setValue(self: Self, row: usize, val: T) void {
            self.slice[row] = val;
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

pub fn DataAdapterBitset(T: type) type {
    return struct {
        const Self = @This();
        bitset: *T,

        pub fn value(self: Self, row: usize) bool {
            return self.bitset.isSet(row);
        }

        pub fn setValue(self: Self, row: usize, val: bool) void {
            self.bitset.setValue(row, val);
        }

        pub fn len(self: Self) usize {
            return self.bitset.capacity();
        }
    };
}

/// TODO: Need to make this work for virtual scrolling!
/// Should we make comptime versions of these that don't need self?
pub fn SliceOfStruct(T: type, field_name: []const u8) type {
    comptime switch (@typeInfo(T)) {
        .@"struct" => {
            if (!@hasField(T, field_name)) {
                @compileError(std.fmt.comptimePrint("{s} does not contain field {s}.", .{ @typeName(T), field_name }));
            }
        },
        else => @compileError(@typeName(T) ++ " is not a slice."),
    };
    return struct {
        const Self = @This();
        slice: []T,

        // These take self so that dataset can change at runtime. But this was originally
        // done as static functions at comptime. Which would be more efficient.
        // Consider making comptime versions?
        pub fn value(self: Self, row: usize) @FieldType(T, field_name) {
            return @field(self.slice[row], field_name);
        }

        pub fn setValue(self: Self, row: usize, val: @FieldType(T, field_name)) void {
            @field(self.slice[row], field_name) = val;
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

pub fn SliceOfStructEnum(T: type, field_name: []const u8) type {
    comptime switch (@typeInfo(T)) {
        .@"struct" => {
            if (!@hasField(T, field_name)) {
                @compileError(std.fmt.comptimePrint("{s} does not contain field {s}.", .{ @typeName(T), field_name }));
            }
        },
        else => @compileError(@typeName(T) ++ " is not a slice."),
    };
    return struct {
        const Self = @This();
        slice: []T,

        // These take self so that dataset can change at runtime. But this was originally
        // done as static functions at comptime. Which would be more efficient.
        // Consider making comptime versions?
        pub fn value(self: Self, row: usize) []const u8 {
            return @tagName(@field(self.slice[row], field_name));
        }

        pub fn setValue(self: Self, row: usize, val: []const u8) void {
            @field(self.slice[row], field_name) = std.meta.stringToEnum(@TypeOf(self.slice[0]), val);
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}
