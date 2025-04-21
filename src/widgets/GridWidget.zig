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
header: BoxWidget = undefined,
body: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined,
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

    self.header = BoxWidget.init(
        @src(),
        .horizontal,
        false,
        self.options.strip().override(.{ .expand = .horizontal, .name = "GridWidget header", .border = dvui.Rect.all(1) }),
    );

    try self.header.install();
    try self.header.drawBackground();
}

/// Start the grid header.
/// Must call defer on the returned widget.
pub fn gridHeader(self: *GridWidget) !void {
    _ = self;
}

/// Start the grid header.
/// Must call defer on the returned widget.
pub fn gridBody(self: *GridWidget) !void {
    self.header.deinit();
    self.scroll = ScrollAreaWidget.init(
        @src(),
        .{ .horizontal = .none },
        self.vbox.data().options.strip().override(.{ .expand = .both, .name = "GridWidget scroll" }),
    );
    try self.scroll.install();
    self.body = BoxWidget.init(
        @src(),
        .horizontal,
        false,
        self.vbox.data().options.strip().override(.{ .expand = .both, .name = "GridWidget body" }),
    );
    try self.body.install();
    try self.body.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.hbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    // TODO: dvui.dataSet(null, self.hbox.data().id, "_scroll_id", self.scroll.wd.id);
    self.body.deinit();
    self.scroll.deinit();
    std.debug.print("DEINIT\n\n", .{});
    self.vbox.deinit();
}

// TODO:
//test {
//    @import("std").testing.refAllDecls(@This());
//}
