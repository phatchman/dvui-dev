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

pub const InitOpts = struct {
    sortFn: ?*const fn (sort_key: []const u8, direction: SortDirection) void,
};

vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,
col_widths: std.ArrayListUnmanaged(f32) = undefined,
num_cols_set: usize = 0,
num_cols_get: usize = 0,
sort_direction: SortDirection = .unsorted,
sort_key: []const u8 = "",

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
    if (self.num_cols_set < self.col_widths.items.len) {
        self.col_widths.items[self.num_cols_set] = w;
    } else {
        try self.col_widths.append(dvui.currentWindow().arena(), w);
    }
    self.num_cols_set += 1;
}

pub fn colWidthGet(self: *GridWidget) f32 {
    if (self.num_cols_get < self.col_widths.items.len) {
        return self.col_widths.items[self.num_cols_get];
    } else {
        // TODO: This should log a debug message. mark in red etc.
        return 0;
    }
    self.num_cols_get += 1;
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
        self.scroll = ScrollAreaWidget.init(src, .{ .horizontal = .none }, .{ .expand = .both });
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
