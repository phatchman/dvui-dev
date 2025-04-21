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

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());

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
        backend.setCursor(win.cursorRequested());
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            try dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

// both dvui and SDL drawing
fn gui_frame() !void {
    const backend = g_backend orelse return;
    _ = backend;

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

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }
    var grid = try dvui.grid(
        @src(),
        .{ .sortFn = sort },
        .{ .expand = .both, .background = true },
    );
    defer grid.deinit();
    {
        var header = try dvui.gridHeader(@src(), .{}, .{});
        defer header.deinit();
        try dvui.gridCheckboxHeader(@src(), grid, .{});
        try dvui.gridHeading(@src(), grid, "Make", .{});
        try dvui.gridHeading(@src(), grid, "Model", .{});
        try dvui.gridHeading(@src(), grid, "Year", .{});
        try dvui.gridHeading(@src(), grid, "Condition", .{});
        try dvui.gridHeading(@src(), grid, "Description", .{});
    }
    {
        var body = try dvui.gridBody(@src(), .{}, .{});
        defer body.deinit();
        const changed = try dvui.gridCheckboxColumn(@src(), grid, Car, cars[0..], "selected", .{});
        //        const changed = try dvui.gridCheckboxColumn(@src(), grid, bool, selections[0..], "0", .{});
        if (changed) std.debug.print("selection changed\n", .{});
        try dvui.gridColumn(@src(), grid, Car, cars[0..], "make", "{s}", .{});
        try dvui.gridColumn(@src(), grid, Car, cars[0..], "model", "{s}", .{});
        try dvui.gridColumn(@src(), grid, Car, cars[0..], "year", "{d}", .{});
        try dvui.gridColumn(@src(), grid, Car, cars[0..], "condition", "{s}", .{});
        try dvui.gridColumn(@src(), grid, Car, cars[0..], "description", "{s}", .{});
    }
    // Sorting / Filtering
    // Pass an optional SortFn and FilterFn
    // FilterFn is done in grid.bind(t: []T) and is applied to each row
    // It is also applied to any checkbox columns, so that the filtered rows will match
    // the selected rows. This needs to be done before the pe-column binds are done:
    // 1) So we know how many entries in the list so we can set the scroll window appropraitely
    // 2) So that we know which checkbox rows to clear (e.g. if they are not in the currrent filter)
    //

    // HMMM?
    // What about derived values e.g. if it is supplied via a function??

}

fn sort(key: []const u8, direction: dvui.GridWidget.SortDirection) void {
    if (std.mem.eql(u8, key, "X")) {
        return;
    }
    switch (direction) {
        .descending => std.mem.sort(Car, &cars, key, sortDesc),
        else => std.mem.sort(Car, &cars, key, sortAsc),
    }
}

fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
    if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
    return std.mem.lessThan(u8, lhs.make, rhs.make);
}

fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
    if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
    return std.mem.lessThan(u8, rhs.make, lhs.make);
}

// I don't think there is any way around making the selection bool part of the same struct as the data.
// Because selection needs to be kept in sync with the data when sorting.
// Otherwise you'd have to sort the selections in the same order as the
// underlying data. This method is way simpler.

// But in theory you could make the checkbox column on a different datastructure to the rest of the data.
// This might be useful if you aren't sorting. But if someone just wants an array of bool, how would that work as ther eif no name to pass to @field?
// Maybe we can special-case for bools?

const Car = struct {
    selected: bool = false,
    model: []const u8,
    make: []const u8,
    year: u32,
    condition: Condition,
    description: []const u8,

    const Condition = enum { New, Excellent, Good, Fair, Poor };
};

var selections: [cars.len]bool = @splat(false);

var cars = [_]Car{
    .{ .model = "Civic", .make = "Honda", .year = 2022, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
    .{ .model = "Civic", .make = "Honda", .year = 2022, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
