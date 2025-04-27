const std = @import("std");
const dvui = @import("../dvui.zig");

// TODO: The first 2 frames don't set the height correctly. Expect only the first frame would have an issue?

const Options = dvui.Options;
const Rect = dvui.Rect;
const Size = dvui.Size;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    // generally the top of a scroll area is against something flat (like
    // window header), and the bottom is against something curved (bottom
    // of a window)
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
};

pub const InitOpts = struct {};
const ColWidth = struct {
    const Owner = enum { header, body };
    owner: Owner,
    width: f32,
    changed_this_frame: bool,
};

vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,
col_widths: std.ArrayListUnmanaged(ColWidth) = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);

    if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []ColWidth)) |col_widths| {
        try self.col_widths.ensureTotalCapacity(dvui.currentWindow().arena(), col_widths.len);
        self.col_widths.appendSliceAssumeCapacity(col_widths);
    } else {
        self.col_widths = .empty;
        // Refresh as body col width not set yet.
    }
    self.options = options;
    return self;
}

pub fn install(self: *GridWidget) !void {
    try self.vbox.install();
    try self.vbox.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    dvui.dataSetSlice(null, self.data().id, "_col_widths", self.col_widths.items[0..]);
    self.vbox.deinit();
}

pub fn colWidthSet(self: *GridWidget, which: ColWidth.Owner, w: f32, col_num: usize) !void {
    if (col_num < self.col_widths.items.len) {
        if (self.col_widths.items[col_num].owner != which or !std.math.approxEqRel(f32, self.col_widths.items[col_num].width, w, 0.01)) {
            if (self.col_widths.items[col_num].changed_this_frame) {
                self.col_widths.items[col_num].changed_this_frame = false;
                return;
            }
            std.debug.print("{} on col {} changed width from {d} to {d}\n", .{ which, col_num, self.col_widths.items[col_num].width, w });
            // If any col widths have changed, need to redraw.
            dvui.refresh(null, @src(), null);
            self.col_widths.items[col_num] = .{ .owner = which, .width = w, .changed_this_frame = true };
        }
    } else {
        std.debug.print("new\n", .{});
        dvui.refresh(null, @src(), null);
        try self.col_widths.append(dvui.currentWindow().arena(), .{ .owner = which, .width = w, .changed_this_frame = true });
    }
}

pub fn colWidthGet(self: *const GridWidget, which: ColWidth.Owner, col_num: usize) f32 {
    if (col_num < self.col_widths.items.len) {
        const col_width = &self.col_widths.items[col_num];
        if (which == col_width.owner or col_width.changed_this_frame) {
            //col_width.changed_this_frame = false; // TODO: This can't go here.
            if (col_width.changed_this_frame) std.debug.print("Changed this frame\n", .{});
            return 0;
        }
        return col_width.width;
    } else {
        // TODO: This should log a debug message. mark in red etc.
        return 0;
    }
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};
    pub const SortDirection = enum {
        unsorted,
        ascending,
        descending,
    };
    pub const SelectionState = enum {
        select_all,
        select_none,
        unchanged,
    };

    pub var defaults: Options = .{
        .name = "GridHeaderWidget",
        // generally the top of a scroll area is against something flat (like
        // window header), and the bottom is against something curved (bottom
        // of a window)
    };

    header_hbox: BoxWidget = undefined,
    col_hbox: ?BoxWidget = null,
    grid: *GridWidget = undefined,
    col_number: usize = 0,
    sort_col_number: usize = 0,
    sort_direction: SortDirection = .unsorted,
    height: f32 = 0,
    height_this_frame: f32 = 0,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        // TODO: Check how other widgets do this initialization
        var self = GridHeaderWidget{};
        const options = GridHeaderWidget.defaults.override(opts);

        _ = init_opts;
        self.grid = grid;
        self.header_hbox = BoxWidget.init(src, .horizontal, false, options);

        if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
            self.sort_col_number = sort_col;
        }
        if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
            self.sort_direction = sort_direction;
        }
        if (dvui.dataGet(null, self.data().id, "_height", f32)) |height| {
            self.height = height;
        }
        //        self.min_size = opts.min_size_content;
        //        self.max_size = opts.max_size_content;

        return self;
    }

    pub fn deinit(self: *GridHeaderWidget) void {
        dvui.dataSet(null, self.data().id, "_height", self.height_this_frame);
        dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
        dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);

        self.header_hbox.deinit();
    }

    pub fn install(self: *GridHeaderWidget) !void {
        try self.header_hbox.install();
        try self.header_hbox.drawBackground();
    }

    pub fn data(self: *GridHeaderWidget) *WidgetData {
        return &self.header_hbox.wd;
    }

    /// Start a new column heading.
    /// must be called before any widgets are created.
    pub fn colBegin(self: *GridHeaderWidget, src: std.builtin.SourceLocation, opts: Options) !void {
        // Check if box is null. Log warning if not.
        // check not in_body. Log warning if not.
        const min_width = self.grid.colWidthGet(.header, self.col_number);

        var col_options: Options = .{
            .min_size_content = .{ .w = min_width, .h = self.height },
            .max_size_content = opts.max_size_content,
        };
        if (opts.min_size_content) |min_size_content| {
            col_options.min_size_content = min_size_content;
        }
        self.col_hbox = BoxWidget.init(src, .horizontal, false, col_options);
        try self.col_hbox.?.install();
        try self.col_hbox.?.drawBackground();
    }

    /// End of a column heading.
    /// must be called after all column widgets are deinit-ed.
    pub fn colEnd(self: *GridHeaderWidget) void {
        // Check in_body, log warning if not?? Needed?
        if (self.col_hbox) |*hbox| {
            const header_width = hbox.data().contentRect().w;
            const header_height = hbox.data().contentRect().h;

            const min_width = self.grid.colWidthGet(.header, self.col_number);

            if (header_width > min_width) {
                self.grid.colWidthSet(.header, header_width, self.col_number) catch unreachable; // TODO: Don't want to throw from a de-init.
                // TODO: Prolly do the refresh in the grid widget?
                //dvui.refresh(null, @src(), null);
            }

            if (header_height > self.height_this_frame) {
                self.height_this_frame = header_height;
            }

            hbox.deinit();
            self.col_hbox = null;
        } // else log warning.

        self.col_number += 1;
    }

    pub fn colWidthGet(self: *GridHeaderWidget) f32 {
        return self.grid.colWidthGet(.header, self.col_number);
    }

    /// Must be called from the column header when the current column's sort order has changed.
    pub fn sortChanged(self: *GridHeaderWidget) void {
        // If sorting on a new column, change current sort column to unsorted.
        if (self.col_number != self.sort_col_number) {
            self.sort_direction = .unsorted;
            self.sort_col_number = self.col_number;
        }
        // If new sort column, then ascending, otherwise opposite of current sort.
        self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
    }

    /// Returns the sort order for the current header.
    pub fn colSortOrder(self: *const GridHeaderWidget) SortDirection {
        if (self.col_number == self.sort_col_number) {
            return self.sort_direction;
        } else {
            return .unsorted;
        }
    }
};

pub const GridBodyWidget = struct {
    pub const defaults: Options = .{
        .name = "GridBodyWidget",
        .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
        // Must either provide .expand or .min_size_content for virtual scrolling to work.
        .expand = .vertical,
    };
    pub const InitOpts = struct {
        scroll_info: ?*ScrollInfo = null,
    };
    grid: *GridWidget = undefined,
    scroll: ScrollAreaWidget = undefined,
    hbox: BoxWidget = undefined,
    col_vbox: ?BoxWidget = null,
    row_hbox: ?BoxWidget = null,
    col_number: usize = 0,
    cell_number: usize = 0,
    // invisible_height is used to pad the top of the scroll area in virtual scrolling mode
    // The padded area will contain the "invisibile" rows at the start of the grid.
    invisible_height: f32 = 0,
    row_height: f32 = 0,
    row_height_this_frame: f32 = 0,
    min_size: ?Size = null,
    max_size: ?Size = null,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridBodyWidget.InitOpts, opts: Options) GridBodyWidget {
        var self = GridBodyWidget{};
        const options = GridBodyWidget.defaults.override(opts);

        self.grid = grid;
        self.scroll = ScrollAreaWidget.init(src, .{ .scroll_info = init_opts.scroll_info }, options);
        // TODO: Somehow check that our parent is the Grid header.
        if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
            self.row_height = row_height;
        }
        self.min_size = opts.min_size_content;
        self.max_size = opts.max_size_content;

        return self;
    }

    pub fn install(self: *GridBodyWidget) !void {
        try self.scroll.install();
        self.hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .vertical });

        try self.hbox.install();
        try self.hbox.drawBackground();
    }

    pub fn deinit(self: *GridBodyWidget) void {
        dvui.dataSet(null, self.data().id, "_row_height", if (self.row_height_this_frame > 0) self.row_height_this_frame else self.row_height);
        self.hbox.deinit();
        self.scroll.deinit();
    }

    pub fn data(self: *GridBodyWidget) *WidgetData {
        return self.scroll.data();
    }

    /// Begin a new grid column
    /// must be called before any widgets are created in the column
    pub fn colBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation, opts: Options) !void {
        // Check if box is null. Log warning if not.

        const min_width = self.grid.colWidthGet(.body, self.col_number);

        var col_options: Options = .{
            .min_size_content = .{ .w = min_width },
            .max_size_content = opts.max_size_content,
        };
        if (opts.min_size_content) |min_size_content| {
            col_options.min_size_content = min_size_content;
        }
        self.col_vbox = BoxWidget.init(src, .vertical, false, col_options);
        try self.col_vbox.?.install();
        try self.col_vbox.?.drawBackground();

        // Create a vbox to pad out space for any invisible rows.
        if (self.invisible_height > 0) {
            var vbox = BoxWidget.init(src, .vertical, false, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = self.invisible_height },
                .max_size_content = .{ .h = self.invisible_height },
            });
            try vbox.install();
            vbox.deinit();
        }
        // TODO: So the issue is we can never shrink because we don't know the header vs body width.
        // Is there a better way that just storing them separately?
    }

    /// End a new column
    /// must be called after all widgets in the column have been deinit-ed.
    pub fn colEnd(self: *GridBodyWidget) void {
        if (self.col_vbox) |*vbox| {
            const current_width = vbox.data().contentRect().w;
            const min_width = self.grid.colWidthGet(.body, self.col_number);

            if (current_width > min_width) {
                // TODO: proll do this in GridWidget?
                //dvui.refresh(null, @src(), null);
                self.grid.colWidthSet(.body, current_width, self.col_number) catch unreachable; // TODO: Don't want to throw from a deinit.
            }
            // TODO: Testing
            //self.grid.colWidthSet(current_width, self.col_number) catch unreachable; // TODO: Don't want to throw from a deinit.

            vbox.deinit();
            self.col_vbox = null;
        } // else log warning.
        self.col_number += 1;
    }

    // Start a new cell.
    // must be called before any widgets are createdf in the cell
    pub fn cellBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation) !void {
        self.row_hbox = BoxWidget.init(src, .horizontal, false, .{ .id_extra = self.cell_number, .expand = .both });
        try self.row_hbox.?.install();
        try self.row_hbox.?.drawBackground();
    }

    // End a new cell
    // must be called after all widgets in the cell have been deinit-ed.
    pub fn cellEnd(self: *GridBodyWidget) void {
        if (self.row_hbox) |*hbox| {
            if (hbox.wd.rect.h > self.row_height_this_frame) {
                self.row_height_this_frame = hbox.wd.rect.h;
            }
            hbox.deinit();
            self.row_hbox = null;
        }
        self.cell_number += 1;
    }
};

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed to as an init_option
/// to the GridBodyWidget.
pub const GridVirtualScroller = struct {
    pub const InitOpts = struct {
        // Total rows in the columns displayed
        total_rows: usize,
        // The number of rows before and after the visible scroll area to load.
        // The larger the window, the smoother the scrolling, at the expense of more rows being rendered.
        window_size: usize = 1,
    };
    body: *GridBodyWidget,
    si: *ScrollInfo,
    total_rows: usize,
    window_size: usize,
    pub fn init(body: *GridBodyWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
        const total_rows_f: f32 = @floatFromInt(init_opts.total_rows);
        body.scroll.si.virtual_size.h = @max(total_rows_f * body.row_height, body.scroll.si.viewport.h);
        const window_size: f32 = @floatFromInt(init_opts.window_size);
        body.invisible_height = @max(0, body.scroll.si.viewport.y - body.row_height * window_size);
        return .{
            .body = body,
            .si = body.scroll.si,
            .total_rows = init_opts.total_rows,
            .window_size = init_opts.window_size,
        };
    }

    /// Return the first row within the visible scroll area, minus window_size
    pub fn rowFirstRendered(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 0;
        }
        const first_row_in_viewport: usize = @intFromFloat(@round(self.si.viewport.y / self.body.row_height));
        if (first_row_in_viewport < self.window_size) {
            return @min(first_row_in_viewport, self.total_rows);
        }
        return @min(first_row_in_viewport - self.window_size, self.total_rows);
    }

    /// Return the first row within the visible scroll area, plus the window size.
    pub fn rowLastRendered(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 1;
        }
        const last_row_in_viewport: usize = @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.body.row_height));
        return @min(last_row_in_viewport + self.window_size, self.total_rows);
    }
};
