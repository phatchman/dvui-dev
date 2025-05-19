const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const ColorOrName = dvui.Options.ColorOrName;
const Rect = dvui.Rect;
const Size = dvui.Size;
const MaxSize = Options.MaxSize;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const GridWidget = @This();

pub const CellOptions = struct {
    height: ?f32 = null,
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_fill_hover: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn toOptions(self: *const CellOptions) Options {
        return .{
            // height is not converted as cell height is set via rect.
            .margin = self.margin,
            .border = self.border,
            .padding = self.padding,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_fill_hover = self.color_fill_hover,
            .color_border = self.color_border,
        };
    }
};

pub const ColOptions = struct {
    width: ?f32 = null,
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_fill_hover: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn toOptions(self: *const ColOptions) Options {
        return .{
            // height is not converted as cell height is set via rect.
            .margin = self.margin,
            .border = self.border,
            .padding = self.padding,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_fill_hover = self.color_fill_hover,
            .color_border = self.color_border,
        };
    }
};

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
    scroll_opts: ?ScrollAreaWidget.InitOpts = null,
    col_widths: ?[]f32 = null,
    //content_width: ?f32, // TODO: Consider adding content width so that user can size the width of the scroll area?
    //equal_row_heights: ?bool // TODO: Consider adding a flag that lets each row height vary independently.
};
pub const default_col_width: f32 = 100;

vbox: BoxWidget = undefined, // Outer container
scroll: ScrollAreaWidget = undefined,
hbox: BoxWidget = undefined, // Horizontal box for column layout
init_opts: InitOpts = undefined,
num_cols: f32 = undefined,
current_col: ?*BoxWidget = null,
next_row_y: f32 = 0,
last_height: f32 = 0,
header_height: f32 = 0,
last_header_height: f32 = 0,
row_height: f32 = 0,
last_row_height: f32 = 0,
tallest_body_col: usize = 0,
col_num: usize = std.math.maxInt(usize),
sort_col_number: usize = 0,
sort_direction: SortDirection = .unsorted,
prev_clip_rect: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);
    if (dvui.dataGet(null, self.data().id, "_last_height", f32)) |last_height| {
        self.last_height = last_height;
    }
    if (dvui.dataGet(null, self.data().id, "_header_height", f32)) |header_height| {
        self.last_header_height = header_height;
    }
    if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
        self.last_row_height = row_height;
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
    self.clipReset();
    dvui.dataSet(null, self.data().id, "_last_height", self.next_row_y);
    dvui.dataSet(null, self.data().id, "_header_height", self.header_height);
    dvui.dataSet(null, self.data().id, "_row_height", self.row_height);
    dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);

    self.hbox.deinit();
    self.scroll.deinit();
    self.vbox.deinit();
    if (!std.math.approxEqAbs(f32, self.header_height, self.last_header_height, 0.01) or
        !std.math.approxEqAbs(f32, self.row_height, self.last_row_height, 0.01))
    {
        dvui.refresh(null, @src(), self.data().id);
    }
}

pub fn column(self: *GridWidget, src: std.builtin.SourceLocation, opts: ColOptions) !*BoxWidget {
    self.clipReset();
    self.current_col = null;
    if (self.col_num == std.math.maxInt(usize)) {
        self.col_num = 0;
    } else {
        self.col_num += 1;
    }
    self.next_row_y = 0;

    const w: f32, const expand: ?Options.Expand = width: {
        // Take width from col_opts if it is set.
        if (self.init_opts.col_widths) |col_info| {
            if (self.col_num < col_info.len) {
                break :width .{ col_info[self.col_num], null };
            } else {
                dvui.log.debug("GridWidget {x} has more columns than set in init_opts.col_info. Using default column width of {d}\n", .{ self.data().id, default_col_width });
                break :width .{ default_col_width, null };
            }
        } else {
            if (opts.width) |w| {
                if (w > 0) {
                    break :width .{ w, null };
                } else if (w == 0) {
                    break :width .{ 0, .horizontal };
                } else {
                    dvui.log.debug("GridWidget {x} invalid opts.width provided to column(). Using default column width of {d}\n", .{ self.data().id, default_col_width });
                    break :width .{ default_col_width, null };
                }
            } else {
                // If there is no width specified either in col_info or col_opts,
                // just expand to fill available width.
                break :width .{ 0, .horizontal };
            }
        }
    };
    var col_opts = opts.toOptions();
    col_opts.expand = expand;
    col_opts.min_size_content = .{ .w = w, .h = self.last_height };
    col_opts.max_size_content = if (w > 0) .width(w) else null;

    var col = try dvui.currentWindow().arena().create(BoxWidget);
    col.* = BoxWidget.init(src, .vertical, false, col_opts);
    try col.install();
    try col.drawBackground();
    self.current_col = col;
    return col;
}

fn clipReset(self: *GridWidget) void {
    if (self.prev_clip_rect) |cr| {
        dvui.clipSet(cr);
        self.prev_clip_rect = null;
    }
}

pub fn headerCell(self: *GridWidget, src: std.builtin.SourceLocation, opts: CellOptions) !*BoxWidget {
    const y = self.scroll.si.viewport.y - 1.0;
    const parent_rect = self.current_col.?.data().contentRect();

    const header_height: f32 = height: {
        if (opts.height) |height| {
            break :height height;
        } else {
            break :height 0;
        }
    };

    var cell_opts = opts.toOptions();
    cell_opts.rect = .{ .x = 0, .y = y, .w = parent_rect.w, .h = header_height };

    // Create the cell and install as parent.
    var cell = try dvui.currentWindow().arena().create(BoxWidget);
    cell.* = BoxWidget.init(src, .horizontal, false, cell_opts);
    try cell.install();
    try cell.drawBackground();

    // Determine heights for next frame.
    if (cell.data().contentRect().h > 0) {
        const height = cell.data().rect.h;
        self.header_height = @max(self.header_height, height);
    }
    self.next_row_y += self.last_header_height; // TODO: Should this really be last_header_height?
    return cell;
}

pub fn bodyCell(self: *GridWidget, src: std.builtin.SourceLocation, row_num: usize, opts: CellOptions) !*BoxWidget {
    const parent_rect = self.current_col.?.data().contentRect();

    const cell_height: f32 = height: {
        if (opts.height) |height| {
            break :height height;
        } else {
            break :height 0;
        }
    };

    // Prevent the header for being overwritten when scrolling.
    if (self.prev_clip_rect == null) {
        const rect_scale = self.vbox.data().rectScale();
        const header_height_scaled = self.last_header_height * rect_scale.s;

        self.prev_clip_rect = dvui.clipGet();
        dvui.clipSet(rect_scale.r.offset(.{ .y = header_height_scaled }));
    }

    var cell_opts = opts.toOptions();
    cell_opts.rect = .{ .x = 0, .y = self.next_row_y, .w = parent_rect.w, .h = cell_height };
    cell_opts.id_extra = row_num;

    var cell = try dvui.currentWindow().arena().create(BoxWidget);
    cell.* = BoxWidget.init(src, .horizontal, false, cell_opts);
    try cell.install();
    try cell.drawBackground();

    if (cell.data().contentRect().h > 0) {
        const measured_cell_height = cell.data().rect.h;
        self.row_height = @max(self.row_height, measured_cell_height);
    }
    self.next_row_y += self.last_row_height; // TODO: Should this really be last_row_height?

    return cell;
}

/// Must be called whenever the sort order for any column has changed.
pub fn sortChanged(self: *GridWidget) void {
    // If sorting on a new column, change current sort column to unsorted.
    if (self.col_num != self.sort_col_number) {
        self.sort_direction = .unsorted;
        self.sort_col_number = self.col_num;
    }
    // If new sort column, then ascending, otherwise opposite of current sort.
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
}

/// Returns the sort order for the current column.
pub fn colSortOrder(self: *const GridWidget) SortDirection {
    if (self.col_num == self.sort_col_number) {
        return self.sort_direction;
    } else {
        return .unsorted;
    }
}

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed as an init_option
/// to the GridBodyWidget.
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
