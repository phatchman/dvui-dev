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

pub var scroll_info: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .given };
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
        .{},
        .{ .expand = .both, .background = true },
    );
    defer grid.deinit();
    {
        var header = try dvui.gridHeader(@src(), grid, .{}, .{});
        defer header.deinit();
        var sort_dir: dvui.GridWidget.SortDirection = undefined;
        var selection: dvui.GridWidget.SelectionState = undefined;
        if (try dvui.gridHeadingCheckBox(@src(), header, &selection, .{})) {
            for (cars[0..]) |*car| {
                switch (selection) {
                    .select_all => car.selected = true,
                    .select_none => car.selected = false,
                    .unchanged => {},
                }
            }
        }
        // TODO: Make grid heading checkbox return the selet all / select none options.
        // User is responsible for doing the select all / none.
        if (try dvui.gridHeadingSortable(@src(), header, "Make", &sort_dir, .{})) {
            sort("Make", sort_dir);
        }
        if (try dvui.gridHeadingSortable(@src(), header, "Model", &sort_dir, .{})) {
            sort("Model", sort_dir);
        }
        if (try dvui.gridHeadingSortable(@src(), header, "Year", &sort_dir, .{})) {
            sort("Year", sort_dir);
        }
        if (try dvui.gridHeadingSortable(@src(), header, "Mileage", &sort_dir, .{})) {
            sort("Mileage", sort_dir);
        }
        if (try dvui.gridHeadingSortable(@src(), header, "Condition", &sort_dir, .{})) {
            sort("Condition", sort_dir);
        }
        if (try dvui.gridHeadingSortable(@src(), header, "Description", &sort_dir, .{})) {
            sort("Description", sort_dir);
        }
    }
    {
        var body = try dvui.gridBody(@src(), grid, .{ .scroll_info = &scroll_info }, .{});
        defer body.deinit();
        var scroller = dvui.GridWidget.GridVirtualScroller.init(body, cars.len);
        const first = scroller.rowFirstVisible();
        const last = scroller.rowLastVisible();

        // TODO: Just handle select-single.
        const changed = try dvui.gridColumnCheckBox(@src(), body, Car, cars[first..last], "selected", .{});
        if (changed) std.debug.print("selection changed\n", .{});

        //std.debug.print("first = {}, last = {}, height = {d}\n", .{ first, last, body.rowHeight() });
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "make", "{s}", .{});
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "model", "{s}", .{});
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "year", "{d}", .{});
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "mileage", "{d}", .{ .gravity_x = 1.0 });
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "condition", "{s}", .{ .gravity_x = 0.5 });
        try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "description", "{s}", .{});
        //std.debug.print("VP = {}\n VS = {} first = {}, last = {}\n", .{ body.scroll.si.viewport, body.scroll.si.virtual_size, first, last });
    }

    // Think about the alternative of 2 blank h/vboxes before and after the grid.

    // OK So in one of the widgets, we need to:
    // 1) Get the height of a single row. (Grid Widget knows this)
    // 2) Get the viewport height. (Body Widget knows this)
    // 3) Calc number of rows to display (From 1 and 2)
    // 4) Calc starting display row.
    // 5) In the display data column, get the start offset and number to display from some widget.
    // 6) Only create labels for the needed rows.

    // HMMM?
    // What about derived values e.g. if it is supplied via a function?? Thinking of things like totals etc.
    // as well as maybe just wanting to format an enum differently.
    // For this they prob need to write their own column.it is quite easy to do now.
    std.debug.print("FPS = {d}\n", .{dvui.FPS()});
}

fn sort(key: []const u8, direction: dvui.GridWidget.SortDirection) void {
    switch (direction) {
        .descending => std.mem.sort(Car, &cars, key, sortDesc),
        else => std.mem.sort(Car, &cars, key, sortAsc),
    }
}

fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
    if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return lhs.mileage < rhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(lhs.condition) < @intFromEnum(rhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, lhs.description, rhs.description);

    return std.mem.lessThan(u8, lhs.make, rhs.make);
}

fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
    if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return rhs.mileage < lhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(rhs.condition) < @intFromEnum(lhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, rhs.description, lhs.description);

    return std.mem.lessThan(u8, rhs.make, lhs.make);
}

// I don't think there is any way around making the selection bool part of the same struct as the data.
// Because selection needs to be kept in sync with the data when sorting.
// Otherwise you'd have to sort the selections in the same order as the
// underlying data. This method is way simpler.
//
// But in theory you could make the checkbox column on a different datastructure to the rest of the data.
// This might be useful if you aren't sorting. But if someone just wants an array of bool, how would that work as ther eif no name to pass to @field?
// Maybe we can special-case for bools?
// !!!!!
// Yes all of the above works now in the PoC. Can either use a separate array of bools or have the bools as a field in the struct.
// But need better syntax.

const Car = struct {
    selected: bool = false,
    model: []const u8,
    make: []const u8,
    year: u32,
    mileage: u32,
    condition: Condition,
    description: []const u8,

    const Condition = enum(u32) { New, Excellent, Good, Fair, Poor };
};

var selections: [cars.len]bool = @splat(false);

var cars = initCars();
const num_cars = 50;
fn initCars() [num_cars]Car {
    comptime var result: [num_cars]Car = undefined;
    comptime {
        @setEvalBranchQuota(num_cars + 1);

        for (0..num_cars) |i| {
            result[i] = some_cars[i % some_cars.len];
            result[i].year = i;
        }
    }
    return result;
}

const some_cars = [_]Car{
    .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },

    .{ .model = "CX-5", .make = "Mazda", .year = 2019, .mileage = 32000, .condition = .Excellent, .description = "Zoom zoom, but responsibly." },
    .{ .model = "Outback", .make = "Subaru", .year = 2017, .mileage = 61000, .condition = .Good, .description = "Always looks ready for a camping trip, even when it's not." },

    .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
