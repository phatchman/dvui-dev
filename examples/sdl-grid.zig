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
        gui_frame();

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
    }
}

var col_widths: [2]f32 = .{ 500, 500 };
var scroll_info: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .auto };
// both dvui and SDL drawing
fn gui_frame() void {
    {
        var m = dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
        }
    }
    var hbox = dvui.box(@src(), .horizontal, .{ .expand = .both, .background = true });
    defer hbox.deinit();
    //var grid = dvui.grid(@src(), .{ .col_widths = &col_widths, .scroll_opts = .{ .scroll_info = &scroll_info, .vertical_bar = .show, .horizontal_bar = .show } }, .{ .expand = .both });
    //var grid = dvui.grid(@src(), .{ .col_widths = &col_widths, .scroll_opts = .{ .vertical_bar = .show, .horizontal_bar = .show } }, .{ .expand = .both });
    //var grid = dvui.grid(@src(), .{ .col_widths = &col_widths }, .{ .expand = .both });
    {
        resize_cols = false;
        const CellStyle = dvui.GridWidget.CellStyle;
        if (true) {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{}); // TODO: No .expand
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .w = 50, .h = 50 } });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
        } else if (true) {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(4) }, .{});
            defer grid.deinit();
            {
                for (0..2) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..4) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
        } else {
            var grid = dvui.grid(@src(), .{ .resize_cols = resize_cols, .cols = .numCols(2), .var_row_heights = false }, .{});
            defer grid.deinit();
            {
                dvui.gridHeading(@src(), grid, "Col 2", 1, .fixed, CellStyle{ .cell_opts = .{ .border = dvui.Rect.all(1), .color_border = .blue } });
            }
            {
                dvui.gridHeading(@src(), grid, "Col 1", 0, .fixed, CellStyle{ .cell_opts = .{ .border = dvui.Rect.all(1), .color_border = .green, .size = .{ .w = 500 } } });

                for (1..15) |i| {
                    const size: ?dvui.Size = if (stepped) .{ .w = @as(f32, @floatFromInt(i * 20)) } else null;
                    var cell = grid.bodyCell(@src(), 1, i - 1, .{ .size = size, .background = true, .color_fill = .fill_hover });
                    defer cell.deinit();
                    dvui.label(@src(), "1:{}", .{i}, .{ .gravity_x = 0.5 });
                }
            }

            {
                for (1..15) |i| {
                    var cell = grid.bodyCell(@src(), 0, i - 1, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "0:{}", .{i}, .{ .gravity_x = 0.5 });
                }
            }

            {
                //                var hcell = grid.headerCell(@src(), 0, .{});
                //                dvui.labelNoFmt(@src(), "Rogue", .{}, .{});
                //                hcell.deinit();
                for (15..30) |i| {
                    {
                        var cell = grid.bodyCell(@src(), 0, 43 - i, .{});
                        defer cell.deinit();
                        dvui.label(@src(), "0:{}", .{44 - i}, .{ .gravity_x = 0.5 });
                    }
                    {
                        var cell = grid.bodyCell(@src(), 1, 43 - i, .{ .background = true, .color_fill = .fill_hover });
                        defer cell.deinit();
                        dvui.label(@src(), "1:{}", .{44 - i}, .{ .gravity_x = 0.5 });
                    }
                }
            }
        }
    }
    std.debug.print(".", .{});
    //    _ = dvui.checkbox(@src(), &stepped, "Stepped?", .{});
    //    _ = dvui.checkbox(@src(), &resize_cols, "Resize Cols?", .{});
}

var stepped = false;
var resize_cols: bool = false;

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
