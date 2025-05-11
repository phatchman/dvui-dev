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
var scale_val: f32 = 1.0;

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
    filtered_cars = try filterCars(gpa, cars[0..], filterLongModels);
    defer gpa.free(filtered_cars);

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
    }
}

const ColumnLayoutProportional = struct {
    const InitOpts = struct {
        // Positive values are treated as fixed width columns
        // Negative values are treated as a ratio.
        initial_w: []f32,
        // Size to specified width. Otherwise sizes to width of parent grid.
        content_w: ?f32 = null,
    };

    // TODO: Probably remove init_opts and make these params?
    pub fn init(grid: *dvui.GridWidget, init_opts: ColumnLayoutProportional.InitOpts) void {
        const scroll_bar_w: f32 = 10; // Don't necessarily know if SB is showing?
        const content_w: f32 = init_opts.content_w orelse grid.data().contentRect().w;

        const reserved_w, const ratio_w: f32 = blk: {
            var res_width: f32 = 0;
            var total_ratio_w: f32 = 0;
            for (init_opts.initial_w) |w| {
                if (w <= 0) {
                    total_ratio_w += -w;
                } else {
                    res_width += w;
                }
            }
            break :blk .{ res_width, total_ratio_w };
        };
        const available_w = content_w - reserved_w - scroll_bar_w;
        for (init_opts.initial_w) |*w| {
            if (w.* <= 0) {
                w.* = -w.* / ratio_w * available_w;
            }
        }
    }
};

const ColumnLayoutEqualWidth = struct {
    const InitOpts = struct {
        // Positive widths are treated as fixed width columns.
        // Zero and negative widths are laid out as equal width
        initial_w: []f32,
        // Size to specified width. Otherwise sizes to width of parent grid.
        content_w: ?f32,
    };

    pub fn init(grid: *dvui.GridWidget, init_opts: ColumnLayoutEqualWidth.InitOpts) void {
        const num_cols: f32, const reserved_w: f32 = blk: {
            var col_count: usize = 0;
            var res_width: f32 = 0;
            for (init_opts.initial_w) |w| {
                if (w <= 0) {
                    col_count += 1;
                } else {
                    res_width += w;
                }
            }
            break :blk .{ @floatFromInt(col_count), res_width };
        };

        const scroll_bar_w: f32 = 10; // Don't necessarily know if SB is showing?
        const content_w: f32 = init_opts.content_w orelse grid.data().contentRect().w;
        const col_width = (content_w - reserved_w - scroll_bar_w) / num_cols;

        for (init_opts.initial_w) |*w| {
            if (w.* <= 0) {
                w.* = col_width;
            }
        }
    }
};

const num_cars = 500;
pub const testing = false;
pub var scroll_info: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .auto };
var virtual_scrolling = false;
var horizontal_scrolling = false;
var sortable = true;
var header_height: f32 = 0;
var row_height: f32 = 0;
var selectable = false;
const ColumnSizing = enum {
    equal_width,
    proportional,
    col_info,
};
var column_sizing: ColumnSizing = .equal_width;
const prev_height: f32 = 0;

const fixed_width_w: f32 = 50;
pub fn headerCheckboxOptions() dvui.Options {
    return .{
        .min_size_content = .{ .w = 40 },
        .max_size_content = .width(40),
    };
}

pub fn rowCheckboxOptions() dvui.Options {
    return headerCheckboxOptions();
}

pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, opts: dvui.Options) !dvui.Rect {
    var lw = dvui.LabelWidget.initNoFmt(src, str, opts);
    try lw.install();
    std.debug.print("clip = {}\n", .{dvui.clipGet()});
    lw.processEvents();
    try lw.draw();
    const rect = lw.data().rect;
    lw.deinit();
    return rect;
}

const col_info_default: [7]f32 = .{ 40, 20, 30, 40, 50, 60, 70 };
const col_info_proportional: [7]f32 = .{ 40, -20, -30, -40, -50, -60, -70 };
var col_info: [col_info_default.len]f32 = col_info_default;

const ColumnLayoutDummy = struct {
    fn nextHeaderColOption(_: *ColumnLayoutDummy, opts: dvui.Options) dvui.Options {
        return opts.override(.{ .max_size_content = .width(0) });
    }

    fn nextBodyColOption(_: *ColumnLayoutDummy, opts: dvui.Options) dvui.Options {
        return opts.override(.{ .max_size_content = .width(0) });
    }
};

// both dvui and SDL drawing
fn gui_frame() !void {
    std.debug.print("frame\n", .{});
    const backend = g_backend orelse return;
    _ = backend;
    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
        }
    }
    if (testing) {
        var outer_vbox = try dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
        defer outer_vbox.deinit();
        {
            var scroll = try dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{ .expand = .both });
            defer scroll.deinit();
            {
                var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
                defer hbox.deinit();
                {
                    var vbox = try dvui.box(@src(), .vertical, .{
                        .expand = .vertical,
                        .min_size_content = .{ .w = 150 },
                        .max_size_content = .width(50),
                        .border = dvui.Rect.all(1),
                    });
                    defer vbox.deinit();
                    try dvui.labelNoFmt(@src(), "Body1", .{});
                }
                {
                    var vbox = try dvui.box(@src(), .vertical, .{
                        .expand = .vertical,
                        .min_size_content = .{ .w = 150 },
                        .max_size_content = .width(50),
                        .border = dvui.Rect.all(1),
                    });
                    defer vbox.deinit();
                    var rect = try labelNoFmt(@src(), "Header 2", .{ .rect = .{ .h = 27.5, .w = 150, .x = 0, .y = 0 } });
                    var hb = try dvui.box(@src(), .horizontal, .{ .expand = .both });
                    defer hb.deinit();
                    var y_pos: f32 = rect.h;
                    //                    const r = dvui.clip(.{ .h = 27.5, .w = 150, .y = y_pos });
                    std.debug.print("clip = {}\n", .{dvui.clipGet()});
                    rect = try labelNoFmt(@src(), "Body2.1", .{ .rect = .{ .h = 27.5, .w = 150, .y = y_pos } });
                    //                    dvui.clipSet(r);
                    y_pos += rect.h;
                    rect = try labelNoFmt(@src(), "Body2.2", .{ .rect = .{ .h = 27.5, .w = 150, .y = y_pos } });
                    y_pos += rect.h;
                    rect = try labelNoFmt(@src(), "Body2.3", .{ .rect = .{ .h = 27.5, .w = 150, .y = y_pos } });
                    y_pos += rect.h;
                    rect = try labelNoFmt(@src(), "Body2.4", .{ .rect = .{ .h = 27.5, .w = 150, .y = y_pos } });
                }
                {
                    var vbox = try dvui.box(@src(), .vertical, .{
                        .expand = .vertical,
                        .min_size_content = .{ .w = 550 },
                        .max_size_content = .width(550),
                        .border = dvui.Rect.all(1),
                    });
                    defer vbox.deinit();
                    try dvui.labelNoFmt(@src(), "Body3", .{});
                }
            }
        }
        return;
    }

    var main_hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .background = true });
    defer main_hbox.deinit();
    {
        scroll_info.horizontal = if (horizontal_scrolling) .auto else .none;
        const start_idx: usize = if (selectable) 0 else 1;

        var grid = try dvui.grid(
            @src(),
            if (virtual_scrolling or true)
                .{
                    .scroll_opts = .{ .scroll_info = &scroll_info },
                    .col_info = col_info[start_idx..], // TODO: Implement a non-col_info version
                }
            else
                .{
                    .horizontal = if (horizontal_scrolling) .auto else .none,
                    .vertical = .auto,
                    .vertical_bar = .show,
                },
            .{
                .expand = .both,
                .background = true,
                .max_size_content = .width(main_hbox.data().contentRect().w - 250),
                // TODO: Why is this 250 and not 200? I think the control panel should only be 200 wide.
                // But if I make this 200, the grid walks it's way from -250 to -200 on startup
            },
        );
        defer grid.deinit();
        const content_w: ?f32 = if (horizontal_scrolling) grid.data().contentRect().w + 1024 else null;
        //        ColumnLayoutEqualWidth.init(grid, .{ .initial_w = &col_info, .content_w = content_w });
        std.debug.print("start idx = {}\n", .{start_idx});
        switch (column_sizing) {
            .equal_width => {
                col_info = @splat(-1);
                col_info[0] = col_info_default[0];
                ColumnLayoutEqualWidth.init(grid, .{ .initial_w = col_info[start_idx..], .content_w = content_w });
            },
            .proportional => {
                @memcpy(col_info[start_idx..], col_info_proportional[start_idx..]);
                ColumnLayoutProportional.init(grid, .{ .initial_w = col_info[start_idx..], .content_w = content_w });
            },
            .col_info => @memcpy(col_info[start_idx..], col_info_default[start_idx..]),
        }
        ColumnLayoutProportional.init(grid, .{ .initial_w = col_info[start_idx..], .content_w = content_w });
        std.debug.print("col_info = {d}\n", .{col_info});
        var layout = ColumnLayoutDummy{};
        //const reserved_w: f32 = if (selectable) headerCheckboxOptions().min_size_content.?.w else 0; // TODO: This is the scroll bar width
        //        var layout: ColumnLayout = switch (column_sizing) {
        //            // TODO: col_info should have a dummy one.
        //            .col_info, .equal_width => .{ .equal_width = ColumnLayoutEqualWidth.init(grid, .{
        //                .reserved_w = reserved_w,
        //                .content_w = content_w,
        //            }, 6) },
        //            .proportional => .{ .proportional = ColumnLayoutProportional.init(
        //                grid,
        //                .{
        //                    .reserved_w = reserved_w,
        //                    .content_w = content_w,
        //                },
        //                &.{ 10, 15, 20, 40, 15, 55 },
        //            ) },
        //        };
        {
            //            var header = try dvui.gridHeader(@src(), grid, .{}, .{ .expand = .horizontal });
            //            defer header.deinit();
            var sort_dir: dvui.GridWidget.SortDirection = undefined;
            var selection: dvui.GridColumnSelectAllState = undefined;
            if (selectable) {
                var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                defer col.deinit();

                if (try dvui.gridHeadingCheckbox(@src(), grid, &selection, headerCheckboxOptions())) {
                    for (cars[0..]) |*car| {
                        switch (selection) {
                            .select_all => car.selected = true,
                            .select_none => car.selected = false,
                            .unchanged => {},
                        }
                    }
                }

                const changed = try dvui.gridColumnCheckbox(@src(), grid, Car, cars[0..], "selected", rowCheckboxOptions());
                if (changed) std.debug.print("selection changed\n", .{});
            }
            if (sortable) {
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();
                    if (try dvui.gridHeadingSortable(@src(), grid, "Make", &sort_dir, .{})) {
                        sort("Make", sort_dir);
                    }
                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "make", "{s}", .{});
                }
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();
                    if (try dvui.gridHeadingSortable(@src(), grid, "Model", &sort_dir, .{})) {
                        std.debug.print("Sorting {s}\n", .{@tagName(sort_dir)});
                        sort("Model", sort_dir);
                    }
                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "model", "{s}", .{});
                }
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();
                    if (try dvui.gridHeadingSortable(@src(), grid, "Year", &sort_dir, .{})) {
                        sort("Year", sort_dir);
                    }
                    try customColumn(@src(), grid, cars[0..], layout.nextHeaderColOption(.{}));
                    //try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "year", "{d}", .{ .gravity_x = 1.0 });
                }
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();

                    if (try dvui.gridHeadingSortable(@src(), grid, "Mileage", &sort_dir, .{})) {
                        sort("Mileage", sort_dir);
                    }
                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "mileage", "{d}", .{ .gravity_x = 1.0 });
                }
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();

                    if (try dvui.gridHeadingSortable(@src(), grid, "Condition", &sort_dir, .{})) {
                        sort("Condition", sort_dir);
                    }
                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "condition", "{s}", .{ .gravity_x = 0.5 });
                }
                {
                    var col = try grid.column(@src(), layout.nextHeaderColOption(.{}).max_size_content.?.w);
                    defer col.deinit();
                    if (try dvui.gridHeadingSortable(@src(), grid, "Description", &sort_dir, .{})) {
                        sort("Description", sort_dir);
                    }
                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "description", "{s}", .{});
                }
            } // else if (false) {
            //   try dvui.gridHeading(@src(), header, "Make", layout.nextHeaderColOption(.{}));
            //   try dvui.gridHeading(@src(), header, "Model", layout.nextHeaderColOption(.{}));
            //   try dvui.gridHeading(@src(), header, "Year", layout.nextHeaderColOption(.{}));
            //   try dvui.gridHeading(@src(), header, "Mileage", layout.nextHeaderColOption(.{}));
            //   try dvui.gridHeading(@src(), header, "Condition", layout.nextHeaderColOption(.{}));
            //   try dvui.gridHeading(@src(), header, "Description", layout.nextHeaderColOption(.{}));
            //}
        }
        if (false) // TODO: Keep scope
        {
            var body = try dvui.gridBody(@src(), grid, .{}, .{ .expand = .both });
            defer body.deinit();
            const row_count = if (filter_grid) filtered_cars.len else cars.len;
            const first, const last = limits: {
                if (virtual_scrolling) {
                    var scroller = body.virtualScroller(.{ .total_rows = row_count, .window_size = 20 });
                    break :limits .{ scroller.rowFirstRendered(), scroller.rowLastRendered() };
                } else {
                    break :limits .{ 0, row_count };
                }
            };

            if (selectable) {
                const changed = try dvui.gridColumnCheckbox(@src(), body, Car, cars[first..last], "selected", rowCheckboxOptions());
                if (changed) std.debug.print("selection changed\n", .{});
            }

            if (!filter_grid) {
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "make", "{s}", layout.nextBodyColOption(.{}));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "model", "{s}", layout.nextBodyColOption(.{}));
                try customColumn(@src(), body, cars[first..last], layout.nextBodyColOption(.{}));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "mileage", "{d}", layout.nextBodyColOption(.{ .gravity_x = 1.0 }));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "condition", "{s}", layout.nextBodyColOption(.{ .gravity_x = 0.5 }));
                try dvui.gridColumnFromSlice(@src(), body, Car, cars[first..last], "description", "{s}", layout.nextBodyColOption(.{}));
            } else {
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "make", "{s}", layout.nextBodyColOption(.{}));
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "model", "{s}", layout.nextBodyColOption(.{}));
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "year", "{d}", layout.nextBodyColOption(.{}));
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "mileage", "{d}", layout.nextBodyColOption(.{ .gravity_x = 1.0 }));
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "condition", "{s}", layout.nextBodyColOption(.{ .gravity_x = 0.5 }));
                try dvui.gridColumnFromSlice(@src(), body, *Car, filtered_cars[first..last], "description", "{s}", layout.nextBodyColOption(.{}));
            }
        }
    }
    {
        // Control panel
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .vertical, .min_size_content = .{ .w = 250 }, .max_size_content = .width(250) });
        defer vbox.deinit();
        try dvui.labelNoFmt(@src(), "Control Panel", .{ .font_style = .title_2 });
        _ = try dvui.checkbox(@src(), &sortable, "sortable", .{});
        _ = try dvui.checkbox(@src(), &virtual_scrolling, "virtual scrolling", .{});
        if (try dvui.expander(@src(), "Column Layout", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var inner_vbox = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
            defer inner_vbox.deinit();
            if (try dvui.radio(@src(), column_sizing == .equal_width, "Equal Spacing", .{})) {
                column_sizing = .equal_width;
            }
            if (try dvui.radio(@src(), column_sizing == .proportional, "Proportional", .{})) {
                column_sizing = .proportional;
            }
            if (try dvui.radio(@src(), column_sizing == .col_info, "col_info", .{})) {
                column_sizing = .col_info;
            }

            //            if (try dvui.radio(@src(), column_sizing == .fixed_width, "Fixed Width", .{})) {
            //                column_sizing = .fixed_width;
            //            }
        }
        _ = try dvui.checkbox(@src(), &horizontal_scrolling, "Horizontal scrolling", .{});
        _ = try dvui.checkbox(@src(), &selectable, "Selection", .{});
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
        {
            if (try dvui.expander(@src(), "Populate From", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
                if (try dvui.checkbox(@src(), &filter_grid, "Filter", .{})) {
                    gpa.free(filtered_cars);
                    filtered_cars = try filterCars(gpa, cars[0..], filterLongModels);
                }
            }
        }
    }
}

fn customColumn(src: std.builtin.SourceLocation, g: *dvui.GridWidget, data: []Car, opts: dvui.Options) !void {
    // TODO: FIX this to have defaults then override. Actually fix this so you just specify column size
    const label_opts = opts.override(.{ .min_size_content = null, .max_size_content = null });
    for (data, 0..) |*item, i| {
        var cell = try g.bodyCell(@src(), i, opts);
        defer cell.deinit();
        try dvui.label(src, "{d}", .{item.year}, label_opts.override(.{
            .id_extra = i,
            .gravity_x = if (item.year % 2 == 0) 0.0 else 1.0,
            .gravity_y = 0.5,
            //   .expand = .both,
        }));
    }
}

// TODO: Is it worth providing in-built support for iterator population?
// the grid is laid out by column, so iterator would need to:
// 1) Implement a count if virtual scrolling.
// 2) Implement a reset of use multiple iterators to lay out each column
// Currently filtering uses a slice of pointers instead of iterators, due to the
// awkward interface.
// At least for large array-based data sets, user can store values in a MultiArrayList
// so that it is optimised for iterating through each colunm.
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

var filtered_cars: []*Car = undefined;

/// Filter the cars data based on the filter function: const fn (*const Car) bool
/// caller is responsible for freeing the returned slice.
fn filterCars(allocator: std.mem.Allocator, src: []Car, filter_fn: fn (*Car) bool) ![]*Car {
    var result: std.ArrayListUnmanaged(*Car) = try .initCapacity(allocator, src.len);
    for (src) |*car| {
        if (filter_fn(car)) { // TODO: FIX
            result.appendAssumeCapacity(car);
        }
    }
    return result.toOwnedSlice(allocator);
}

fn filterLongModels(car: *const Car) bool {
    return (car.model.len < 10);
}

fn sort(key: []const u8, direction: dvui.GridWidget.SortDirection) void {
    switch (direction) {
        .descending,
        => std.mem.sort(Car, &cars, key, sortDesc),
        .ascending,
        .unsorted,
        => std.mem.sort(Car, &cars, key, sortAsc),
    }
}

fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
    if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return lhs.mileage < rhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(lhs.condition) < @intFromEnum(rhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, lhs.description, rhs.description);
    // default sort on Make
    return std.mem.lessThan(u8, lhs.make, rhs.make);
}

fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
    if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return rhs.mileage < lhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(rhs.condition) < @intFromEnum(lhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, rhs.description, lhs.description);

    // default sort on Make
    return std.mem.lessThan(u8, rhs.make, lhs.make);
}

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
    .{ .model = "Mustang with a really long name", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
