//! DataAdapters provide ....
//! All DataAdapters must implement
//! - pub fn value(row_num: usize) T
//! - pub fn setValue(row_num: usize, val: T) void
//! - pub fn len() usize
//!

const std = @import("std");

/// This DataAdapter returns the same void value for all rows and columns
/// You almost certainly want to use one of the specialised adapters.
// TODO: This doesn't yet work for virtual scrolling.
// The adapaters either needs to take a start / end index or a start_offset or similar
// as we only want the user to pass the visible part of the dataset to the adapters.
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

pub fn Bitset(T: type) type {
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

// TODO: There will end up being be Slice and SliceOfStruct versions of everything...
// That's probably fine, but would be nice to avoid it.
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

        // Convert enum to string
        pub fn value(self: Self, row: usize) []const u8 {
            return @tagName(@field(self.slice[row], field_name));
        }

        // Convert string to enum.
        pub fn setValue(self: Self, row: usize, val: []const u8) void {
            if (std.meta.stringToEnum(@TypeOf(self.slice[0]), val)) |new_val| {
                @field(self.slice[row], field_name) = new_val;
            }
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

pub fn SliceOfStructEnumLookup(StructT: type, field_name: []const u8, EnumArrayT: type) type {
    // TODO: Put this in some common validation functions.
    comptime switch (@typeInfo(StructT)) {
        .@"struct" => {
            if (!@hasField(StructT, field_name)) {
                @compileError(std.fmt.comptimePrint("{s} does not contain field {s}.", .{ @typeName(StructT), field_name }));
            }
        },
        else => @compileError(@typeName(StructT) ++ " is not a struct."),
    };
    return struct {
        const Self = @This();
        icon_map: EnumArrayT,
        slice: []StructT,

        // Convert enum to string
        pub fn value(self: Self, row: usize) EnumArrayT.Value {
            const field_value: EnumArrayT.Key = @field(self.slice[row], field_name);
            return self.icon_map.get(field_value);
        }

        /// HMMM???
        pub fn setValue(_: Self, _: usize, _: EnumArrayT.Value) void {
            @compileError("setValue() not supported");
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}
