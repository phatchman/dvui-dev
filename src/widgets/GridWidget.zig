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

pub const InitOpts = struct {};

vbox: BoxWidget = undefined,
//header: BoxWidget = undefined,
//body: BoxWidget = undefined,
//scroll: ScrollAreaWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);

    self.vbox = BoxWidget.init(src, .vertical, false, options);

    self.options = options;
    return self;
}

pub fn install(self: *GridWidget) !void {
    try self.vbox.install();
    try self.vbox.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.hbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    self.vbox.deinit();
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};

    hbox: BoxWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        var self = GridHeaderWidget{};
        const options = defaults.override(opts);

        self.hbox = BoxWidget.init(src, .horizontal, false, options);

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

    pub fn data(self: *GridHeaderWidget) *WidgetData {
        return &self.hbox.wd;
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

    pub fn data(self: *GridBodyWidget) *WidgetData {
        return &self.scroll.wd;
    }
};

// TODO:
//test {
//    @import("std").testing.refAllDecls(@This());
//}
