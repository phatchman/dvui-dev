const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = true;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;
var g_backend: ?Backend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();
    //backend.log_events = true;

    _ = Backend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        try gui_frame();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            try dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

const Data = struct {
    selected: bool = false,
    value: usize,
};

var data1 = makeData(20);
var data2 = makeData(20);

fn makeData(num: usize) [num]Data {
    var result: [num]Data = undefined;
    for (1..num) |i| {
        result[i] = .{ .value = i };
    }
    return result;
}

var selections: [data2.len]bool = @splat(false);
var select_bitset: std.StaticBitSet(data2.len) = .initEmpty();

// both dvui and SDL drawing
fn gui_frame() !void {
    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }
    }
    const local = struct {
        var selection_info: dvui.SelectionInfo = .{
            .mode = .multiple,
        };
        var selector: MultiSelectMouse = .{ .selection_info = &selection_info };
        var frame_count: usize = 0;
    };

    var grid = try dvui.grid(@src(), .{}, .{ .expand = .both });
    defer grid.deinit();

    const data = if (local.frame_count % 2 == 0) &data1 else &data2;
    defer local.frame_count += 1;
    //std.debug.print("shift held = {}\n", .{local.shift_held});
    var selection_changed = false;
    local.selector.processEvents();
    //const adapter = DataAdapterStructSlice(Data, "selected", &data, "{s}");
    //const adapter = DataAdapterSlice(bool){ .slice = &selections };
    const adapter = DataAdapterBitset(@TypeOf(select_bitset)){ .bitset = &select_bitset };
    //var selector: SingleSelect = .{ .selection_info = &local.selection_info };

    {
        var col = try grid.column(@src(), .{});
        defer col.deinit();
        var selection: dvui.GridColumnSelectAllState = undefined;
        _ = try dvui.gridHeadingCheckbox(@src(), grid, &selection, .{});
        selection_changed = try dvui.gridColumnCheckboxData(@src(), grid, adapter, .{}, &local.selection_info);
    }
    {
        var col = try grid.column(@src(), .{});
        defer col.deinit();
        try dvui.gridHeading(@src(), grid, "Value", .fixed, .{});
        try dvui.gridColumnFromDataAdapter(@src(), grid, "{d}", DataAdapterStructSlice(Data, "value"){ .slice = data }, .{});
    }
    if (true) {
        //    selector.performAction(selection_changed, adapter);
        local.selector.performAction(selection_changed, adapter);
    }
}

/// TODO: Need to make this work for virtual scrolling!
/// Should we make comptime versions of these that don't need self?
pub fn DataAdapterStructSlice(T: type, field_name: []const u8) type {
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
        pub const data_type = T;
        slice: []T,

        // These take self so that dataset can change at runtime. But this was originally
        //
        pub fn value(self: Self, row: usize) @FieldType(T, field_name) {
            return @field(self.slice[row], field_name);
        }

        pub fn valuePtr(self: Self, row: usize) *@FieldType(T, field_name) {
            return &@field(self.slice[row], field_name);
        }

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

pub fn DataAdapterSlice(T: type) type {
    return struct {
        const Self = @This();
        pub const data_type = T;
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
        pub const data_type = bool;
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

pub const SingleSelect = struct {
    selection_info: *dvui.SelectionInfo,

    pub fn performAction(self: *SingleSelect, selection_changed: bool, data_adapter: anytype) void {
        if (selection_changed) {
            const last_selected = self.selection_info.prev_changed orelse return;
            data_adapter.setValue(last_selected, false);
        }
    }
};

pub const MultiSelectMouse = struct {
    selection_info: *dvui.SelectionInfo,
    shift_held: bool = false,

    pub fn processEvents(self: *MultiSelectMouse) void {
        const evts = dvui.events();
        for (evts) |*e| {
            if (e.evt == .key and (e.evt.key.code == .left_shift or e.evt.key.code == .right_shift)) {
                switch (e.evt.key.action) {
                    .repeat, .down => self.shift_held = true,
                    .up => self.shift_held = false,
                }
            }
        }
    }

    pub fn performAction(self: *const MultiSelectMouse, selection_changed: bool, data_adapter: anytype) void {
        if (selection_changed and self.shift_held) {
            const this_selection = self.selection_info.this_changed orelse return;
            const prev_selection = self.selection_info.prev_changed orelse return;
            const first = @min(this_selection, prev_selection);
            const last = @max(this_selection, prev_selection);
            for (first..last + 1) |row| {
                data_adapter.setValue(row, self.selection_info.this_selected);
            }
        }
    }
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
