const std = @import("std");
const dvui = @import("../dvui.zig");

// TODO: The first 2 frames don't set the height correctly. Expect only the first frame would have an issue?

// TODO: Remove unused.
const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    //    .background = true,
    // generally the top of a scroll area is against something flat (like
    // window header), and the bottom is against something curved (bottom
    // of a window)
    //    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
};

pub const SortDirection = enum {
    unsorted,
    ascending,
    descending,
};

pub const SelectionState = enum { select_all, select_none, unchanged }; // TODO: Move this

pub const InitOpts = struct {};

vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,
col_widths: std.ArrayListUnmanaged(f32) = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);

    if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []f32)) |col_widths| {
        try self.col_widths.ensureTotalCapacity(dvui.currentWindow().arena(), col_widths.len);
        self.col_widths.appendSliceAssumeCapacity(col_widths);
    } else {
        self.col_widths = .empty;
        // Refresh as body col width not set yet.
    }
    //    std.debug.print("Got {d}\n", .{self.col_widths.items});
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

pub fn colWidthSet(self: *GridWidget, w: f32, col_num: usize) !void {
    if (col_num < self.col_widths.items.len) {
        self.col_widths.items[col_num] = w;
    } else {
        try self.col_widths.append(dvui.currentWindow().arena(), w);
    }
}

pub fn colWidthGet(self: *const GridWidget, col_num: usize) f32 {
    if (col_num < self.col_widths.items.len) {
        return self.col_widths.items[col_num];
    } else {
        // TODO: This should log a debug message. mark in red etc.
        return 0;
    }
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};

    header_hbox: BoxWidget = undefined,
    col_hbox: ?BoxWidget = null,
    grid: *GridWidget,
    col_number: usize = 0,
    sort_col_number: usize = 0,
    sort_direction: SortDirection = .unsorted,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        var self = GridHeaderWidget{ .grid = grid };
        const options = defaults.override(opts);

        _ = init_opts;
        // _ = options;
        self.header_hbox = BoxWidget.init(src, .horizontal, false, options);

        if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
            self.sort_col_number = sort_col;
        }

        if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
            self.sort_direction = sort_direction;
        } else {
            self.sort_direction = .unsorted;
        }

        return self;
    }

    pub fn deinit(self: *GridHeaderWidget) void {
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

    pub fn colBegin(self: *GridHeaderWidget, src: std.builtin.SourceLocation) !void {
        // Check if box is null. Log warning if not.
        // check not in_body. Log warning if not.
        const min_width = self.grid.colWidthGet(self.col_number);
        self.col_hbox = BoxWidget.init(src, .horizontal, false, .{ .min_size_content = .{ .w = min_width } });
        try self.col_hbox.?.install();
        try self.col_hbox.?.drawBackground();
    }

    pub fn colEnd(self: *GridHeaderWidget) void {
        // Check in_body, log warning if not?? Needed?
        if (self.col_hbox) |*hbox| {
            const header_width = self.col_hbox.?.data().contentRect().w;
            const min_width = self.grid.colWidthGet(self.col_number);

            if (header_width > min_width) {
                self.grid.colWidthSet(header_width, self.col_number) catch unreachable; // TODO: Don't want to throw from a de-init.
                dvui.refresh(null, @src(), null);
            }

            hbox.deinit();
            self.col_hbox = null;
        } // else log warning.

        self.col_number += 1;
    }

    pub fn sortChanged(self: *GridHeaderWidget) void {
        if (self.col_number != self.sort_col_number) {
            self.sort_direction = .unsorted;
            self.sort_col_number = self.col_number;
        }
        self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
    }

    pub fn colSortOrder(self: *const GridHeaderWidget) SortDirection {
        if (self.col_number == self.sort_col_number) {
            return self.sort_direction;
        } else {
            return .unsorted;
        }
    }
};

pub const GridVirtualScroller = struct {
    body: *GridBodyWidget,
    si: *ScrollInfo,
    total_rows: usize,
    pub fn init(body: *GridBodyWidget, total_rows: usize) GridVirtualScroller {
        body.scroll.si.virtual_size.h = @max(@as(f32, @floatFromInt(total_rows)) * body.row_height, body.scroll.si.viewport.h);
        body.invisible_height = body.scroll.si.viewport.y;

        return .{
            .body = body,
            .si = body.scroll.si,
            .total_rows = total_rows,
        };
    }

    pub fn rowFirstVisible(self: *const GridVirtualScroller) usize {
        return @intFromFloat(@round(self.si.viewport.y / self.body.row_height));
    }

    pub fn rowLastVisible(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 1;
        } else {
            return @min(@as(usize, @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.body.row_height))), self.total_rows);
        }
    }
};

pub const GridBodyWidget = struct {
    pub const InitOpts = struct {
        scroll_info: ?*ScrollInfo = null,
    };
    grid: *GridWidget,
    scroll: ScrollAreaWidget = undefined,
    hbox: BoxWidget = undefined,
    col_vbox: ?BoxWidget = null,
    row_hbox: ?BoxWidget = null,
    //row_hbox: ?BoxWidget = null,
    col_number: usize = 0,
    row_number: usize = 0,
    invisible_height: f32 = 0,
    row_height: f32 = 0,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridBodyWidget.InitOpts, opts: Options) GridBodyWidget {
        var self = GridBodyWidget{ .grid = grid };
        const options = defaults.override(opts);

        // TODO: If we provide out own scroll_info, then we can't set the scroll_info here as it might be a pointer to a stack object.
        self.scroll = ScrollAreaWidget.init(src, .{ .scroll_info = init_opts.scroll_info }, .{ .expand = .both });
        // TODO: Somehow check that our parent is the Grid header.
        // TODO: options
        //self.init_opts = init_opts;
        if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
            self.row_height = row_height;
        } else {
            self.row_height = 1;
        }
        _ = options;
        return self;
    }

    pub fn install(self: *GridBodyWidget) !void {
        try self.scroll.install();
        self.hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .vertical });

        try self.hbox.install();
        try self.hbox.drawBackground();
    }

    pub fn deinit(self: *GridBodyWidget) void {
        dvui.dataSet(null, self.data().id, "_row_height", self.row_height);
        self.hbox.deinit();
        self.scroll.deinit();
    }

    pub fn data(self: *GridBodyWidget) *WidgetData {
        return self.scroll.data();
    }

    pub fn colBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation) !void {
        // Check if box is null. Log warning if not.

        const min_width = self.grid.colWidthGet(self.col_number);

        self.col_vbox = BoxWidget.init(src, .vertical, false, .{ .min_size_content = .{ .w = min_width }, .expand = .none });
        try self.col_vbox.?.install();
        try self.col_vbox.?.drawBackground();

        // Create a big vbox to pad out space for any invisible rows.
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

    // TODO: Should the count go on the begin??
    pub fn colEnd(self: *GridBodyWidget) void {
        if (self.col_vbox) |*vbox| {
            const current_width = vbox.data().contentRect().w;
            const min_width = self.grid.colWidthGet(self.col_number);

            if (current_width > min_width) {
                // TODO:
                dvui.refresh(null, @src(), null);
                self.grid.colWidthSet(current_width, self.col_number) catch unreachable; // TODO: Don't want to throw from a deinit.
            }

            vbox.deinit();
            self.col_vbox = null;
        } // else log warning.
        self.col_number += 1;
    }

    //    // TODO: Checks for null / not null / ordering etc.
    pub fn cellBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation) !void {
        self.row_hbox = BoxWidget.init(src, .horizontal, false, .{ .id_extra = self.row_number });
        try self.row_hbox.?.install();
        try self.row_hbox.?.drawBackground();
    }

    pub fn cellEnd(self: *GridBodyWidget) void {
        if (self.row_hbox) |*hbox| {
            if (hbox.wd.rect.h > self.row_height) {
                self.row_height = hbox.wd.rect.h;
            }
            if (self.row_number == 0) {
                std.debug.print("h = {d}\n", .{hbox.wd.rect.h});
            }
            hbox.deinit();
            self.row_hbox = null;
        }
        self.row_number += 1;
    }

    pub fn firstCellHeight(self: *GridBodyWidget) f32 {
        return self.row_height;
    }
};
