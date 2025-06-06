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
const Direction = enums.Direction;

const GrabHandleWidget = @This();

pub const InitOptions = struct {
    // Initial and resulting width (.vertical) or height (.horizontal)
    value: *f32,
    // clicking on these extra pixels before/after (.vertical)
    // or above/below the handle (.horizontal) also count
    // as clicking on the handle.
    grab_tolerance: f32 = 5,
    // Will not resize to less than this value
    min_size: ?f32 = null,
    // Will not resize to more than this value
    max_size: ?f32 = null,
};

const defaults: Options = .{
    .name = "GrabHandle",
    .background = true, // TODO: remove this when border and background are no longer coupled
    .color_fill = .{ .name = .border },
    .min_size_content = .{ .w = 1, .h = 1 },
};

wd: WidgetData = undefined,
direction: Direction = undefined,
init_opts: InitOptions = undefined,
// This offset is used to keep the mouse pointer and drag handle
// synchronized when the user drags less than the min or more
// than the max size.
offset: Point = .{},
grid: *dvui.GridWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, dir: Direction, init_options: InitOptions, opts: Options) GrabHandleWidget {
    var self = GrabHandleWidget{};

    var widget_opts = defaults.override(opts);
    widget_opts.expand = switch (dir) {
        .horizontal => .horizontal,
        .vertical => .vertical,
    };
    self.direction = dir;
    self.init_opts = init_options;
    self.wd = WidgetData.init(src, .{}, widget_opts);

    if (dvui.dataGet(null, self.wd.id, "_offset", Point)) |offset| {
        self.offset = offset;
    }

    return self;
}

pub fn install(self: *GrabHandleWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
}

pub fn matchEvent(self: *GrabHandleWidget, e: *Event) bool {
    var rs = self.wd.rectScale();

    // Clicking near the handle counts as clicking on the handle.
    const grab_extra = self.init_opts.grab_tolerance * rs.s;
    switch (self.direction) {
        .vertical => {
            rs.r.x -= grab_extra;
            rs.r.w += grab_extra;
        },
        .horizontal => {
            rs.r.y -= grab_extra;
            rs.r.h += grab_extra;
        },
    }
    return dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r });
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
        const cursor: enums.Cursor = switch (self.direction) {
            .vertical => .arrow_w_e,
            .horizontal => .arrow_n_s,
        };

        if (true) {
            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data());
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
                self.offset = .{};
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // stop possible drag and capture
                dvui.captureMouse(null);
                dvui.dragEnd();
                self.offset = .{};
                self.grid.scrollContentSizeUnlock();
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    self.grid.scrollContentSizeLock();
                    switch (self.direction) {
                        .vertical => {
                            //const init_w = self.init_opts.value.*;
                            const unclamped_width = self.init_opts.value.* + dps.x / rs.s + self.offset.x;
                            self.init_opts.value.* = std.math.clamp(
                                unclamped_width,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.x = unclamped_width - self.init_opts.value.*;
                        },
                        .horizontal => {
                            const unclamped_height = self.init_opts.value.* + dps.y / rs.s + self.offset.y;
                            self.init_opts.value.* = std.math.clamp(
                                unclamped_height,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.y = unclamped_height - self.init_opts.value.*;
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
    dvui.dataSet(null, self.wd.id, "_offset", self.offset);
}

test {
    @import("std").testing.refAllDecls(@This());
}
