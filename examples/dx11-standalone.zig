const std = @import("std");
const dvui = @import("dvui");
const Backend = dvui.backend;
const win32 = Backend.win32;
const builtin = @import("builtin");

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const ExtraWindow = struct {
    state: *Backend.WindowState,
    backend: Backend.Context,
    fn deinit(self: ExtraWindow) void {
        self.backend.deinit();
        gpa.destroy(self.state);
    }
};
var extra_windows: std.ArrayListUnmanaged(ExtraWindow) = .{};

const vsync = true;

var show_dialog_outside_frame: bool = false;

const window_class = win32.L("DvuiStandaloneWindow");

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    defer _ = gpa_instance.deinit();

    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }

    Backend.RegisterClass(window_class, .{}) catch win32.panicWin32(
        "RegisterClass",
        win32.GetLastError(),
    );

    var window_state: Backend.WindowState = undefined;

    // init dx11 backend (creates and owns OS window)
    const first_backend = try Backend.initWindow(&window_state, .{
        .registered_class = window_class,
        .dvui_gpa = gpa,
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI DX11 Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer first_backend.deinit();

    defer {
        for (extra_windows.items) |window| {
            window.deinit();
        }
        extra_windows.deinit(gpa);
    }

    const win = first_backend.getWindow();
    while (true) switch (Backend.serviceMessageQueue()) {
        .queue_empty => {
            // beginWait coordinates with waitTime below to run frames only when needed
            const nstime = win.beginWait(first_backend.hasEvent());

            // marks the beginning of a frame for dvui, can call dvui functions after this
            try win.begin(nstime);

            // both dvui and dx11 drawing
            try gui_frame();

            // marks end of dvui frame, don't call dvui functions after this
            // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
            _ = try win.end(.{});

            for (extra_windows.items) |window| {
                try window.backend.getWindow().begin(nstime);
                try gui_frame();
                _ = try window.backend.getWindow().end(.{});
            }

            // cursor management
            first_backend.setCursor(win.cursorRequested());

            // Example of how to show a dialog from another thread (outside of win.begin/win.end)
            if (show_dialog_outside_frame) {
                show_dialog_outside_frame = false;
                try dvui.dialog(@src(), .{}, .{ .window = win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
            }
        },
        .quit => break,
        .close_windows => {
            if (first_backend.receivedClose())
                break;
            extras: while (true) {
                const index: usize = blk: {
                    for (extra_windows.items, 0..) |window, i| {
                        if (window.backend.receivedClose()) break :blk i;
                    }
                    break :extras;
                };
                const window = extra_windows.swapRemove(index);
                window.deinit();
            }
        },
    };
}
const Data = struct {
    selected: bool = false,
    value: usize,
};

var data = makeData();

fn makeData() [20]Data {
    var result: [20]Data = undefined;
    for (1..20) |i| {
        result[i] = .{ .value = i };
    }
    return result;
}
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
        var shift_held = false;
    };

    // Mouse selection
    // 1) Need to know the last selected item
    // 2) Was it selected or unselected?
    // 3) Need to know if ctrl/shift is selected. (using the platform-specific translation)
    // 4) Need to know new_selection

    var grid = try dvui.grid(@src(), .{}, .{ .expand = .both });
    defer grid.deinit();

    local.shift_held = _: {
        const evts = dvui.events();
        for (evts) |*e| {
            if (e.evt == .key and (e.evt.key.code == .left_shift or e.evt.key.code == .right_shift)) {
                switch (e.evt.key.action) {
                    .down => {
                        std.debug.print("DOWN!!\n", .{});
                        break :_ true;
                    },
                    .up => {
                        std.debug.print("UP!!\n", .{});
                        break :_ false;
                    },
                    .repeat => {
                        break :_ local.shift_held;
                    },
                }
            }
        }
        break :_ local.shift_held;
    };
    //std.debug.print("shift held = {}\n", .{local.shift_held});
    var selection_changed = false;
    {
        var col = try grid.column(@src(), .{});
        defer col.deinit();
        var selection: dvui.GridColumnSelectAllState = undefined;
        _ = try dvui.gridHeadingCheckbox(@src(), grid, &selection, .{});
        selection_changed = try dvui.gridColumnCheckbox(@src(), grid, Data, &data, "selected", .{}, &local.selection_info);
    }
    {
        var col = try grid.column(@src(), .{});
        defer col.deinit();
        try dvui.gridHeading(@src(), grid, "Value", .fixed, .{});
        try dvui.gridColumnFromSlice(@src(), grid, Data, &data, "value", "{d}", .{});
    }
    if (true) {
        blk: {
            if (selection_changed and local.shift_held) {
                const this_selection = local.selection_info.this_changed orelse break :blk;
                const prev_selection = local.selection_info.prev_changed orelse break :blk;
                const first = @min(this_selection, prev_selection);
                const last = @max(this_selection, prev_selection);
                for (data[first..last]) |*item| {
                    item.selected = local.selection_info.prev_selected;
                }
            }
        }
    }
    //std.debug.print("last selection = {}\n", .{local.selection_info});
}

const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
