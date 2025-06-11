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

var data = makeData();

fn makeData() [20]Data {
    var result: [20]Data = undefined;
    for (1..20) |i| {
        result[i] = .{ .value = i };
    }
    return result;
}

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
                    .repeat, .down => {
                        std.debug.print("DOWN!!\n", .{});
                        break :_ true;
                    },
                    .up => {
                        std.debug.print("UP!!\n", .{});
                        break :_ false;
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
    //std.debug.print("last selection = {}\n", .{local.selection_info});
}

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
