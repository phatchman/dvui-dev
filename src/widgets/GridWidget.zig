const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const Size = dvui.Size;
const MaxSize = Options.MaxSize;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
};

pub const SortDirection = enum {
    unsorted,
    ascending,
    descending,
};

pub const InitOpts = struct {
    scroll_opts: ?ScrollAreaWidget.InitOpts,
    col_info: ?[]f32,
};

vbox: BoxWidget = undefined,
hbox: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined,
init_opts: InitOpts = undefined,
num_cols: f32 = undefined,
current_col: ?*BoxWidget = null,
next_row_y: f32 = 0,
last_height: f32 = 0,
header_rect: Rect = .{},
col_num: usize = std.math.maxInt(usize),
sort_col_number: usize = 0,
sort_direction: SortDirection = .unsorted,
clip_rect: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);
    if (dvui.dataGet(null, self.data().id, "_last_height", f32)) |last_height| {
        self.last_height = last_height;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
        self.sort_col_number = sort_col;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
        self.sort_direction = sort_direction;
    }

    return self;
}

pub fn install(self: *GridWidget) !void {
    try self.vbox.install();
    try self.vbox.drawBackground();

    self.scroll = ScrollAreaWidget.init(@src(), self.init_opts.scroll_opts orelse .{}, .{ .expand = .both });
    try self.scroll.install();

    // Lay out columns horizontally.
    self.hbox = BoxWidget.init(@src(), .horizontal, false, .{
        .expand = .both,
        .border = Rect.all(1),
    });
    try self.hbox.install();
    try self.hbox.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    self.resetClip();
    dvui.dataSet(null, self.data().id, "_last_height", self.next_row_y);
    dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);

    self.hbox.deinit();
    self.scroll.deinit();
    self.vbox.deinit();
}

// TODO: Decide whether this takes a width or an Option or both.
// The option should be used for background colours for the column, borders etc. (Keep in mind the border will include the header)
pub fn colBegin(self: *GridWidget, src: std.builtin.SourceLocation, col_width: f32) !*BoxWidget {
    // TODO: Should this take styling options?
    // TODO: Check current col is null or else error.
    self.resetClip();
    self.current_col = null;
    if (self.col_num == std.math.maxInt(usize)) {
        self.col_num = 0;
    } else {
        self.col_num += 1;
    }
    self.next_row_y = 0;

    // Width comes from init_opts.col_opts or from col_width.
    const w = width: {
        if (self.init_opts.col_info) |col_info| {
            if (self.col_num < col_info.len) {
                break :width col_info[self.col_num];
            } else {
                break :width col_width;
            }
        } else {
            break :width col_width;
        }
    };

    var col = try dvui.currentWindow().arena().create(BoxWidget);
    col.* = BoxWidget.init(src, .vertical, false, .{
        .expand = .vertical,
        .min_size_content = .{ .w = w, .h = self.last_height },
        .max_size_content = .width(w),
        .border = Rect.all(1),
        .color_border = .{ .color = try dvui.Color.fromHex("#ff0000".*) },
    });
    try col.install();
    try col.drawBackground();
    self.current_col = col;
    return col;
}

fn resetClip(self: *GridWidget) void {
    if (self.clip_rect) |cr| {
        dvui.clipSet(cr);
        self.clip_rect = null;
    }
}

//pub fn colEnd(self: *GridWidget) void {
//    if (self.clip_rect) |cr| {
//        dvui.clipSet(cr);
//        self.clip_rect = null;
//    }
//
//    if (self.current_col) |*current_col| {
//        current_col.deinit();
//        self.current_col = null;
//    } else {
//        // TODO: Some sort of error.
//    }
//    self.col_num += 1;
//}

pub fn headerCell(self: *GridWidget, src: std.builtin.SourceLocation, opts: dvui.Options) !*BoxWidget {
    // TODO: Safety checks
    _ = opts; // TODO: Chose which opts to take.
    const y = self.scroll.si.viewport.y - 1.0;
    const parent_rect = self.current_col.?.data().backgroundRect();

    //    self.resetClip();

    var cell = try dvui.currentWindow().arena().create(BoxWidget);
    cell.* = BoxWidget.init(src, .horizontal, false, .{
        .expand = .horizontal, // TODO: Both?
        .rect = .{ .x = 0, .y = y, .w = parent_rect.w },
        //        .color_fill = .{ .name = .fill_window },
        //        .background = true,
        .border = Rect.all(1),
        .color_border = .{ .color = try dvui.Color.fromHex("#0000ff".*) },
    });
    try cell.install();
    try cell.drawBackground(); // TODO: These background draws prob not required?
    self.next_row_y += cell.data().rect.h;
    self.header_rect = cell.data().rect;
    return cell;
}

pub fn bodyCell(self: *GridWidget, src: std.builtin.SourceLocation, row_num: usize, opts: dvui.Options) !*BoxWidget {
    _ = opts; // TODO: Choose which opts to take.
    const parent_rect = self.current_col.?.data().contentRect();
    const cell_rect: Rect = .{ .x = 0, .y = self.next_row_y, .w = parent_rect.w };
    var cell = try dvui.currentWindow().arena().create(BoxWidget);
    cell.* = BoxWidget.init(src, .horizontal, false, .{
        .id_extra = row_num,
        .rect = cell_rect,
    });

    try cell.install();
    try cell.drawBackground(); // TODO: These background draws prob not required?
    self.next_row_y += cell.data().rect.h;

    if (self.clip_rect == null) {
        self.clip_rect = dvui.clipGet();
        dvui.clipSet(self.vbox.data().rectScale().r.offset(.{ .y = 80 })); // TODO: This should be scaled header height.
    }
    return cell;
}

pub fn sortChanged(self: *GridWidget) void {
    // If sorting on a new column, change current sort column to unsorted.
    if (self.col_num != self.sort_col_number) {
        self.sort_direction = .unsorted;
        self.sort_col_number = self.col_num;
    }
    // If new sort column, then ascending, otherwise opposite of current sort.
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
}

/// Returns the sort order for the current header.
pub fn colSortOrder(self: *const GridWidget) SortDirection {
    if (self.col_num == self.sort_col_number) {
        return self.sort_direction;
    } else {
        return .unsorted;
    }
}

///// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
///// GridVirtualScroller requires that a scroll_info has been passed as an init_option
///// to the GridBodyWidget.
pub const GridVirtualScroller = struct {
    pub const InitOpts = struct {
        // Total rows in the columns displayed
        total_rows: usize,
        // The number of rows to render before and after the visible scroll area.
        // Larger windows can result in smoother scrolling but will take longer to render each frame.
        window_size: usize = 1,
    };
    body: *GridWidget,
    si: *ScrollInfo,
    total_rows: usize,
    window_size: usize,
    pub fn init(body: *GridWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
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

    /// Return the last row within the visible scroll area, plus the window size.
    /// TODO: This doesn't return the last row. It returns the last row + 1? Or at least it needs to for first..last to work.
    pub fn rowLastRendered(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 1;
        }
        const last_row_in_viewport: usize = @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.body.row_height));
        return @min(last_row_in_viewport + self.window_size, self.total_rows);
    }
};
