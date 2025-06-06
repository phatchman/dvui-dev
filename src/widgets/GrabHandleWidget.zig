const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const enums = dvui.enums;

const GrabHandleWidget = @This();

pub const InitOptions = struct {
    direction: enums.Direction,
    w: *f32,
    grab_extra_w: f32 = 5,
    min_width: ?f32 = null,
    max_width: ?f32 = null,
};

const defaults: Options = .{
    .name = "Grab",
    .background = true, // TODO: remove this when border and background are no longer coupled
    .color_fill = .{ .name = .border },
    .min_size_content = .{ .w = 1, .h = 1 },
    //    .margin = .{ .x = 5, .w = 5 },
};

wd: WidgetData = undefined,
init_opts: InitOptions = undefined,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) GrabHandleWidget {
    var self = GrabHandleWidget{};

    var widget_opts = defaults.override(opts);
    widget_opts.expand = switch (init_options.direction) {
        .horizontal => .horizontal,
        .vertical => .vertical,
    };

    self.init_opts = init_options;
    self.wd = WidgetData.init(src, .{}, widget_opts);

    return self;
}

pub fn install(self: *GrabHandleWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}

pub fn matchEvent(self: *GrabHandleWidget, e: *Event) bool {
    if (false) {
        return dvui.eventMatchSimple(e, self.data());
    } else {
        var rs = self.wd.rectScale();

        const grab_pad = self.init_opts.grab_extra_w;
        switch (self.init_opts.direction) {
            .vertical => {
                rs.r.w += grab_pad * rs.s;
            },
            .horizontal => {
                rs.r.h += grab_pad * rs.s;
            },
        }

        return dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r });
    }
}

pub fn processEvents(self: *GrabHandleWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn data(self: *GrabHandleWidget) *WidgetData {
    return &self.wd;
}

pub fn processEvent(self: *GrabHandleWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.evt == .mouse) {
        const rs = self.wd.rectScale();
        const cursor: enums.Cursor = switch (self.init_opts.direction) {
            .vertical => .arrow_w_e,
            .horizontal => .arrow_n_s,
        };

        if (true) {
            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data());
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // stop possible drag and capture
                dvui.captureMouse(null);
                dvui.dragEnd();
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    switch (self.init_opts.direction) {
                        .vertical => {
                            self.init_opts.w.* += dps.x / rs.s;
                            self.init_opts.w.* = std.math.clamp(self.init_opts.w.*, self.init_opts.min_width orelse 1, self.init_opts.max_width orelse dvui.max_float_safe);
                        },
                        .horizontal => {
                            self.init_opts.w.* += dps.y / rs.s;
                        },
                    }
                }
            } else if (e.evt.mouse.action == .position) {
                dvui.cursorSet(cursor);
            }
        }
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *GrabHandleWidget) void {
    _ = self;
}

test {
    @import("std").testing.refAllDecls(@This());
}
