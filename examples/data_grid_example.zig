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
var filter_grid = false;

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
const testing = false;

var first_frame = true;
pub var scroll_info: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .given };
const use_iterator = false;
var virtual_scrolling = true;
var sortable = true;
var header_height: f32 = 0;
var row_height: f32 = 0;
const ColumnSizing = enum {
    size_content,
    size_window,
    size_ratio,
    fixed_width,
};
var column_sizing: ColumnSizing = .size_content;

const fixed_width_w: f32 = 50;
pub fn headerOptions(ratio_w: f32) dvui.Options {
    const default_header_options: dvui.Options = .{};

    var opts = switch (column_sizing) {
        .size_content => default_header_options,
        .size_window => default_header_options.override(.{ .expand = .horizontal }),
        .size_ratio => default_header_options.override(.{ .expand = .ratio, .min_size_content = .{ .w = ratio_w } }),
        .fixed_width => default_header_options.override(.{ .min_size_content = .{ .w = fixed_width_w }, .max_size_content = .{ .w = fixed_width_w } }),
    };
    if (header_height > 0) {
        if (opts.min_size_content) |*min_size_content| {
            min_size_content.h = header_height;
        } else {
            opts.min_size_content = .{ .h = header_height };
        }
    }
    return opts;
}

pub fn headerCheckboxOptions() dvui.Options {
    var opts = headerOptions(0);
    if (opts.min_size_content) |*min_size_content| {
        min_size_content.w = 0;
    }
    if (opts.max_size_content) |*max_size_content| {
        max_size_content.w = 0;
    }
    opts.expand = .none;
    return opts;
}

pub fn rowOptions(ratio_w: f32) dvui.Options {
    const default_row_options: dvui.Options = .{};
    var opts = switch (column_sizing) {
        .size_content => default_row_options,
        .size_window => default_row_options.override(.{ .expand = .horizontal }),
        .size_ratio => default_row_options.override(.{ .expand = .ratio, .min_size_content = .{ .w = ratio_w } }),
        .fixed_width => default_row_options.override(.{ .min_size_content = .{ .w = fixed_width_w }, .max_size_content = .{ .w = fixed_width_w } }),
    };
    if (row_height > 0) {
        if (opts.min_size_content) |*min_size_content| {
            min_size_content.h = row_height;
        } else {
            opts.min_size_content = .{ .h = row_height };
        }
    }
    return opts;
}

pub fn rowCheckboxOptions() dvui.Options {
    var opts = rowOptions(0);
    if (opts.min_size_content) |*min_size_content| {
        min_size_content.w = 0;
    }
    if (opts.max_size_content) |*max_size_content| {
        max_size_content.w = 0;
    }
    opts.expand = .none;
    return opts;
}

// both dvui and SDL drawing
fn gui_frame() !void {
    const backend = g_backend orelse return;
    _ = backend;
    defer first_frame = false;
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
    if (testing) {
        var outer_hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .background = true });
        defer outer_hbox.deinit();

        {
            var vb1 = try dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
            defer vb1.deinit();
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Ahhhhhhh", .{ .expand = .horizontal });
        }
        {
            var vb1 = try dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
            defer vb1.deinit();
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Ahhhhhhh", .{ .expand = .horizontal });
        }
        {
            var vb1 = try dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
            defer vb1.deinit();
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Ahhhhhhh", .{ .expand = .horizontal });
        }

        return;
    }
    var main_hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .background = true });
    defer main_hbox.deinit();
    {
        var grid = try dvui.grid(
            @src(),
            .{},
            .{
                .expand = .both,
                .background = true,
                .max_size_content = .{ .w = main_hbox.data().contentRect().w - 200 },
            },
        );
        defer grid.deinit();
        {
            var header = try dvui.gridHeader(@src(), grid, .{}, .{ .expand = .horizontal });
            defer header.deinit();
            var sort_dir: dvui.GridHeaderWidget.SortDirection = undefined;
            var selection: dvui.GridHeaderWidget.SelectionState = undefined;

            if (try dvui.gridHeadingCheckbox(@src(), header, &selection, headerCheckboxOptions())) {
                for (cars[0..]) |*car| {
                    switch (selection) {
                        .select_all => car.selected = true,
                        .select_none => car.selected = false,
                        .unchanged => {},
                    }
                }
            }

            if (sortable) {
                //std.debug.print("INITIAL OPTS = {}\n", .{headerOptions(0)});
                if (try dvui.gridHeadingSortable(@src(), header, "Make", &sort_dir, headerOptions(30))) {
                    sort("Make", sort_dir);
                }
                if (try dvui.gridHeadingSortable(@src(), header, "Model", &sort_dir, headerOptions(40))) {
                    sort("Model", sort_dir);
                }
                if (try dvui.gridHeadingSortable(@src(), header, "Year", &sort_dir, headerOptions(50))) {
                    sort("Year", sort_dir);
                }
                if (try dvui.gridHeadingSortable(@src(), header, "Mileage", &sort_dir, headerOptions(60))) {
                    sort("Mileage", sort_dir);
                }
                if (try dvui.gridHeadingSortable(@src(), header, "Condition", &sort_dir, headerOptions(70))) {
                    sort("Condition", sort_dir);
                }
                //                if (try dvui.gridHeadingSortable(@src(), header, "Description", &sort_dir, headerOptions(80))) {
                //                    sort("Description", sort_dir);
                //                }
            } else {
                //                try dvui.gridHeading(@src(), header, "Make", opts);
                //                try dvui.gridHeading(@src(), header, "Model", opts);
                //                try dvui.gridHeading(@src(), header, "Year", opts);
                //                try dvui.gridHeading(@src(), header, "Mileage", opts);
                //                try dvui.gridHeading(@src(), header, "Condition", opts);
                //try dvui.gridHeading(@src(), header, "Description", opts);
            }
        }

        {
            var body = try dvui.gridBody(@src(), grid, .{ .scroll_info = if (virtual_scrolling) &scroll_info else null }, .{ .expand = .both });
            defer body.deinit();
            var cars_iterator: CarsIterator = .init(cars[0..], if (filter_grid) filterLongModels else null);
            const row_count = if (use_iterator) cars_iterator.count() else cars.len;
            const first, const last = limits: {
                if (virtual_scrolling) {
                    var scroller = dvui.GridWidget.GridVirtualScroller.init(body, .{ .total_rows = row_count, .window_size = 20 });
                    break :limits .{ scroller.rowFirstRendered(), scroller.rowLastRendered() };
                } else {
                    break :limits .{ 0, row_count };
                }
            };
            //std.debug.print("first = {}, last = {}\n", .{ first, last });

            const changed = try dvui.gridColumnCheckbox(@src(), body, Car, cars[first..last], "selected", rowCheckboxOptions());
            if (changed) std.debug.print("selection changed\n", .{});

            if (!use_iterator) {
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "make", "{s}", rowOptions(30));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "model", "{s}", rowOptions(40));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "year", "{d}", rowOptions(50));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "mileage", "{d}", rowOptions(60).override(.{ .gravity_x = 1.0 }));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "condition", "{s}", rowOptions(70).override(.{ .gravity_x = 0.5 }));
                //try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "description", "{s}", rowOptions(80));
                //try dvui.gridColumnFromSlice(@src(), body, bool, selections[first..last], null, "{s}", .{});
                //try dvui.gridColumnFromSlice(@src(), body, usize, other_data[first..last], null, "{d}", .{});
            } else {
                var iter = CarsIterator.init(cars[first..last], if (filter_grid) filterLongModels else null);
                try dvui.gridColumnFromIterator(@src(), body, &iter, "make", "{s}", rowOptions(20));
                iter.reset();
                try dvui.gridColumnFromIterator(@src(), body, &iter, "model", "{s}", rowOptions(20));
                iter.reset();
                try dvui.gridColumnFromIterator(@src(), body, &iter, "year", "{d}", rowOptions(20));
                iter.reset();
                try dvui.gridColumnFromIterator(@src(), body, &iter, "mileage", "{d}", rowOptions(20).override(.{ .gravity_x = 1.0 }));
                iter.reset();
                try dvui.gridColumnFromIterator(@src(), body, &iter, "condition", "{s}", rowOptions(20).override(.{ .gravity_x = 0.5 }));
                //iter.reset();
                //try dvui.gridColumnFromIterator(@src(), body, &iter, "description", "{s}", rowOptions(20));
            }
            //std.debug.print("VP = {}\n VS = {} first = {}, last = {}\n", .{ body.scroll.si.viewport, body.scroll.si.virtual_size, first, last });
        }
    }
    {
        // Control panel
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .vertical, .min_size_content = .{ .w = 250 }, .max_size_content = .{ .w = 250 } });
        defer vbox.deinit();
        try dvui.labelNoFmt(@src(), "Control Panel", .{ .font_style = .caption_heading });
        _ = try dvui.checkbox(@src(), &sortable, "sortable", .{});
        _ = try dvui.checkbox(@src(), &virtual_scrolling, "virtual scrolling", .{});
        if (try dvui.expander(@src(), "Column Layout", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var inner_vbox = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
            defer inner_vbox.deinit();
            if (try dvui.radio(@src(), column_sizing == .size_content, "Size to content", .{})) {
                column_sizing = .size_content;
            }
            if (try dvui.radio(@src(), column_sizing == .size_window, "Size to window", .{})) {
                column_sizing = .size_window;
            }
            if (try dvui.radio(@src(), column_sizing == .size_ratio, "Size to window (ratio)", .{})) {
                column_sizing = .size_ratio;
            }
            if (try dvui.radio(@src(), column_sizing == .fixed_width, "Fixed Width", .{})) {
                column_sizing = .fixed_width;
            }
        }
        {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Header Height: ", .{});
            const result = try dvui.textEntryNumber(@src(), f32, .{ .value = if (header_height == 0) null else &header_height }, .{});
            if (result.enter_pressed and result.value == .Valid) {
                header_height = result.value.Valid;
            }
        }
        {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Row Height: ", .{});
            const result = try dvui.textEntryNumber(@src(), f32, .{ .value = if (row_height == 0) null else &row_height }, .{});
            if (result.enter_pressed and result.value == .Valid) {
                row_height = result.value.Valid;
            }
        }
        _ = try dvui.checkbox(@src(), &filter_grid, "Filter", .{});
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
    // std.debug.print("FPS = {d}\n", .{dvui.FPS()});
}

const CarsIterator = struct {
    const FilterFN = *const fn (car: *const Car) bool;
    filter_fn: FilterFN = undefined,
    index: usize,
    cars: []Car,

    pub fn init(_cars: []Car, filter_fn: ?FilterFN) CarsIterator {
        return .{
            .index = 0,
            .cars = _cars,
            .filter_fn = filter_fn orelse filterNone,
        };
    }

    pub fn next(self: *CarsIterator) ?*Car {
        while (self.index < self.cars.len) : (self.index += 1) {
            if (self.filter_fn(&cars[self.index])) {
                self.index += 1;
                return &cars[self.index - 1];
            }
        }
        return null;
    }

    pub fn reset(self: *CarsIterator) void {
        self.index = 0;
    }

    pub fn count(self: *CarsIterator) usize {
        var result_count: usize = 0;
        var count_itr: CarsIterator = .init(self.cars, self.filter_fn);
        while (count_itr.next() != null) {
            result_count += 1;
        }
        return result_count;
    }

    fn filterNone(_: *const Car) bool {
        return true;
    }
};

fn filterLongModels(car: *const Car) bool {
    return (car.model.len < 10);
}

fn sort(key: []const u8, direction: dvui.GridHeaderWidget.SortDirection) void {
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

var selections: [num_cars]bool = @splat(false);

var cars = initCars();
const num_cars = 250;
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

var other_data = blk: {
    var tmp: [num_cars]usize = undefined;
    for (0..num_cars) |i| {
        tmp[i] = i;
    }
    break :blk tmp;
};

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
    .{ .model = "Mustang with a really long name", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
