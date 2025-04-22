const std = @import("std");
const dvui = @import("../dvui.zig");

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

pub const SelectionState = enum { select_all, select_none, unchanged };

pub const InitOpts = struct {
    sortFn: ?*const fn (sort_key: []const u8, direction: SortDirection) void = null,
};

vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,
col_widths: std.ArrayListUnmanaged(f32) = undefined,
col_number: usize = 0,
num_cols_get: usize = 0,
col_hvbox: ?dvui.BoxWidget = null,
sort_direction: SortDirection = .unsorted,
sort_key: []const u8 = "",
selection_state: SelectionState = .unchanged,
in_body: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);

    self.vbox = BoxWidget.init(src, .vertical, false, options);
    if (dvui.dataGet(null, self.data().id, "_sort_key", []const u8)) |sort_key| {
        self.sort_key = sort_key;
    }

    if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
        self.sort_direction = sort_direction;
    } else {
        self.sort_direction = .unsorted;
    }

    if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []f32)) |col_widths| {
        try self.col_widths.ensureTotalCapacity(dvui.currentWindow().arena(), col_widths.len);
        self.col_widths.appendSliceAssumeCapacity(col_widths);
    } else {
        // Need to refresh first display frame as the header column widths
        // were not set yet.
        dvui.refresh(null, @src(), null);
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
    dvui.dataSet(null, self.data().id, "_sort_key", self.sort_key);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);
    self.vbox.deinit();
}

pub fn colWidthSet(self: *GridWidget, w: f32) !void {
    if (self.col_number < self.col_widths.items.len) {
        self.col_widths.items[self.col_number] = w;
    } else {
        try self.col_widths.append(dvui.currentWindow().arena(), w);
    }
}

pub fn beginHeaderCol(self: *GridWidget, src: std.builtin.SourceLocation) !void {
    // Check if box is null. Log warning if not.
    // check not in_body. Log warning if not.
    const min_width = self.colWidthGet();
    self.col_hvbox = BoxWidget.init(src, .horizontal, false, .{ .min_size_content = .{ .w = min_width } });
    try self.col_hvbox.?.install();
    try self.col_hvbox.?.drawBackground();
}

pub fn endHeaderCol(self: *GridWidget) void {
    // Check in_body, log warning if not?? Needed?
    if (self.col_hvbox) |*hbox| {
        const header_width = self.col_hvbox.?.data().contentRect().w;
        const min_width = self.colWidthGet();

        if (header_width > min_width) {
            self.colWidthSet(header_width) catch unreachable; // TODO: Don't want to throw from a de-init.
        }

        hbox.deinit();
        self.col_hvbox = null;
    } // else log warning.

    self.col_number += 1;
}

pub fn beginBodyCol(self: *GridWidget, src: std.builtin.SourceLocation) !void {
    // Check if box is null. Log warning if not.

    if (!self.in_body) {
        self.col_number = 0;
        self.in_body = true;
    }
    const min_width = self.colWidthGet();

    self.col_hvbox = BoxWidget.init(src, .vertical, false, .{ .min_size_content = .{ .w = min_width }, .expand = .vertical });
    try self.col_hvbox.?.install();
    try self.col_hvbox.?.drawBackground();

    // TODO: So the issue is we can never shrink because we don't know the header vs body width.
    // Is there a better way that just storing them separately?
}

pub fn endBodyCol(self: *GridWidget) void {
    if (self.col_hvbox) |*vbox| {
        const current_width = self.col_hvbox.?.data().contentRect().w;
        const min_width = self.colWidthGet();

        if (current_width > min_width) {
            self.colWidthSet(current_width) catch unreachable; // TODO: Don't want to throw from a deinit.
        }

        vbox.deinit();
        self.col_hvbox = null;
    } // else log warning.
    self.col_number += 1;
}

pub fn colWidthGet(self: *GridWidget) f32 {
    if (self.col_number < self.col_widths.items.len) {
        return self.col_widths.items[self.col_number];
    } else {
        // TODO: This should log a debug message. mark in red etc.
        return 0;
    }
}

pub fn sort(self: *GridWidget, sort_key: []const u8) void {
    if (!std.mem.eql(u8, sort_key, self.sort_key)) {
        self.sort_direction = .unsorted;
        self.sort_key = sort_key;
    }
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
    if (self.init_opts.sortFn) |sort_fn| {
        sort_fn(sort_key, self.sort_direction);
    }
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};

    hbox: BoxWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        var self = GridHeaderWidget{};
        const options = defaults.override(opts);
        self.hbox = BoxWidget.init(src, .horizontal, false, options);
        // TODO: Validate that ourt parent is a GridWidget.
        _ = init_opts;
        // _ = options;
        return self;
    }

    pub fn install(self: *GridHeaderWidget) !void {
        try self.hbox.install();
        try self.hbox.drawBackground();
    }

    pub fn deinit(self: *GridHeaderWidget) void {
        self.hbox.deinit();
    }
};

pub const GridBodyWidget = struct {
    pub const InitOpts = struct {};

    scroll: ScrollAreaWidget = undefined,
    hbox: BoxWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: GridBodyWidget.InitOpts, opts: Options) GridBodyWidget {
        var self = GridBodyWidget{};
        const options = defaults.override(opts);
        self.scroll = ScrollAreaWidget.init(src, .{ .horizontal = .auto }, .{ .expand = .both });
        // TODO: Somehow check that our parent is the Grid header.
        // TODO: options
        _ = init_opts;
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
        self.hbox.deinit();
        self.scroll.deinit();
    }
};
