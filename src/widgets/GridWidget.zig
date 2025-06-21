// TODO: Need to make
// TODO: We don't currently support ".expand" (i.e. when no width is provided) because we were relying on vboxes for that.
// So either need to re-implement the .expand or make that the user's responsiblity?
// TODO: If col widths allocation fails, then just return the default col width if that column doesn't exist.
// TODO: set the col_widths struct if the widdth param is passed to a cell. Also the .expand handling if width is 0.
// TODO: Variable row heights and next_row_y - style layouts
// TODO: Passing mouse scroll events from header to body
// TODO: Turn row and col num into a Cell-Co-ords type? We're now always using them in pairs.

const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const ColorOrName = Options.ColorOrName;
const Rect = dvui.Rect;
const Size = dvui.Size;
const Point = dvui.Point;
const Direction = dvui.enums.Direction;
const Cursor = dvui.enums.Cursor;
const MaxSize = Options.MaxSize;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const Event = dvui.Event;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const ScrollContainerWidget = dvui.ScrollContainerWidget;
const ScrollBarWidget = dvui.ScrollBarWidget;

pub const CellStyle = @import("GridWidget/CellStyle.zig");
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
    // Small padding to separate first column from left edge of the grid
    .padding = .{ .x = 5 },
};

pub var scrollbar_padding_defaults: Size = .{ .h = 10, .w = 10 };

pub const CellOptions = struct {
    // Manually control height or width
    // height must be consistent for all columns in a row
    // width must be consistent for all rows in a column (including the header cell)
    size: ?Size = null,
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_fill_hover: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn height(self: *const CellOptions) f32 {
        return if (self.size) |size| size.h else 0;
    }

    pub fn width(self: *const CellOptions) f32 {
        return if (self.size) |size| size.w else 0;
    }

    pub fn toOptions(self: *const CellOptions) Options {
        return .{
            // does not convert size, but maybe it should now... hmmm???
            .margin = self.margin,
            .border = self.border,
            .padding = self.padding,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_fill_hover = self.color_fill_hover,
            .color_border = self.color_border,
        };
    }

    pub fn override(self: *const CellOptions, over: CellOptions) CellOptions {
        var ret = self.*;

        inline for (@typeInfo(CellOptions).@"struct".fields) |f| {
            if (@field(over, f.name)) |fval| {
                @field(ret, f.name) = fval;
            }
        }

        return ret;
    }
};

pub const SortDirection = enum {
    unsorted,
    ascending,
    descending,

    pub fn reverse(dir: SortDirection) SortDirection {
        return switch (dir) {
            .descending => .ascending,
            else => .descending,
        };
    }
};

pub const InitOpts = struct {
    scroll_opts: ?ScrollAreaWidget.InitOpts = null,
    col_widths: ?[]f32 = null,
    // Recalculate row heights. Only set this when row heights could have changed, .e.g on column resize.
    resize_rows: bool = false,
    // TODO: Not currently supported.
    // var row heights will place some restrictions on population order
    // and need need to keep track of the next row y, rather than calculating the position
    // and also calculate the grid scroll height differently.
    variable_row_heights: bool = false,
};
pub const default_col_width: f32 = 100;

vbox: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined,
hscroll: ?ScrollAreaWidget = null,
bscroll: ?ScrollContainerWidget = undefined,
bbox: BoxWidget = undefined,
hsi: ScrollInfo = undefined,
bsi: *ScrollInfo = undefined,
default_scroll_info: ScrollInfo = .{ .horizontal = .auto, .vertical = .auto },
init_opts: InitOpts = undefined,
last_height: f32 = 0,
header_height: f32 = 0,
row_height: f32 = 0,
last_row_height: f32 = 0,
sort_col_number: usize = 0,
sort_direction: SortDirection = .unsorted,
saved_clip_rect: ?Rect.Physical = null,
resizing: bool = false,
rows_y_offset: f32 = 0,
max_row: usize = 0,
// TODO: User might need to specify number of cols as an init_opts,
// as otherwise we have to dynamically create the col_opts array as max_cols increases.
max_col: usize = 0,
frame_viewport: Point = undefined,
col_widths_store: std.ArrayListUnmanaged(f32) = .empty,
col_widths: []f32 = undefined,

var frame_count: usize = 0;
pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) GridWidget {
    frame_count += 1;
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .{ .dir = .vertical }, options);
    if (dvui.dataGet(null, self.data().id, "_last_height", f32)) |last_height| {
        self.last_height = last_height;
    }
    if (dvui.dataGet(null, self.data().id, "_resizing", bool)) |resizing| {
        self.resizing = resizing;
    }
    if (dvui.dataGet(null, self.data().id, "_header_height", f32)) |header_height| {
        self.header_height = header_height;
    }
    if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
        self.last_row_height = row_height;
        self.row_height = row_height;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
        self.sort_col_number = sort_col;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
        self.sort_direction = sort_direction;
    }
    if (dvui.dataGet(null, self.data().id, "_hsi", ScrollInfo)) |hsi| {
        self.hsi = hsi;
    } else {
        self.hsi = .{ .horizontal = .auto, .vertical = .none };
    }

    if (dvui.dataGet(null, self.data().id, "_default_si", ScrollInfo)) |default_si| {
        self.default_scroll_info = default_si;
    }
    if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []f32)) |col_widths| {
        self.col_widths_store.appendSlice(dvui.currentWindow().arena(), col_widths) catch {}; // TODO
    }

    // Ensure resize on first initialization.
    if (self.last_height == 0) {
        self.resizing = true;
    }
    if (init_opts.resize_rows or self.resizing) {
        self.row_height = 0;
        dvui.refresh(null, @src(), self.data().id);
    }

    return self;
}

pub fn install(self: *GridWidget) void {
    self.col_widths = self.init_opts.col_widths orelse self.col_widths_store.items;
    if (self.init_opts.scroll_opts) |*scroll_opts| {
        if (scroll_opts.scroll_info) |scroll_info| {
            self.bsi = scroll_info;
        } else {
            self.bsi = &self.default_scroll_info;
            scroll_opts.scroll_info = self.bsi;
        }
    } else {
        self.bsi = &self.default_scroll_info;
    }

    self.frame_viewport = self.bsi.viewport.topLeft();

    self.vbox.install();
    self.vbox.drawBackground();

    const scroll_opts: ScrollAreaWidget.InitOpts = self.init_opts.scroll_opts orelse .{ .frame_viewport = self.frame_viewport, .scroll_info = self.bsi };

    self.scroll = ScrollAreaWidget.init(
        @src(),
        scroll_opts,
        .{
            .name = "GridWidgetScrollArea",
        },
    );
    self.scroll.installScrollBars();
}

pub fn deinit(self: *GridWidget) void {
    defer self.* = undefined;
    defer dvui.widgetFree(self);

    if (self.hsi.viewport.x != self.frame_viewport.x) self.hsi.viewport.x = self.bsi.viewport.x; // TODO

    // resizing if row heights changed or a resize was requested via init options.
    self.resizing =
        self.init_opts.resize_rows or
        !std.math.approxEqAbs(f32, self.row_height, self.last_row_height, 0.01);

    if (self.hscroll) |*hscroll| {
        hscroll.deinit();
    }

    // TODO: Is this bbox guaranteed to exit?
    if (self.bscroll) |*bscroll| {
        self.bbox.deinit();
        bscroll.deinit();
    }
    self.scroll.deinit();
    // TODO: Broken for no columns and for variable row heights.
    const max_row_f: f32 = @floatFromInt(self.max_row);
    dvui.dataSet(null, self.data().id, "_last_height", (max_row_f + 1) * self.row_height);
    dvui.dataSet(null, self.data().id, "_header_height", self.header_height);
    dvui.dataSet(null, self.data().id, "_resizing", self.resizing);
    dvui.dataSet(null, self.data().id, "_row_height", self.row_height);
    dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);
    dvui.dataSet(null, self.data().id, "_hsi", self.hsi);
    if (self.bsi == &self.default_scroll_info) {
        dvui.dataSet(null, self.data().id, "_default_si", self.default_scroll_info); // TODO: Can just  be default as well?
    }
    dvui.dataSetSlice(null, self.data().id, "_col_widths", self.col_widths_store.items);

    self.vbox.deinit();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

fn extendColIfRequired(self: *GridWidget, col_num: usize) void {
    // TODO: Could just check if col_widths == &col_widths_store?
    if (self.init_opts.col_widths) |col_widths| {
        std.debug.assert(col_num < col_widths.len);
    } else if (col_num >= self.col_widths_store.items.len) {
        self.col_widths_store.appendNTimes(dvui.currentWindow().arena(), default_col_width, col_num + 1 - self.col_widths_store.items.len) catch {}; // TODO:
        self.col_widths = self.col_widths_store.items;
    }
}

fn headerScrollAreaCreate(self: *GridWidget, col_num: usize) void {
    self.max_col = @max(self.max_col, col_num);
    if (self.hscroll == null) {
        self.hscroll = ScrollAreaWidget.init(@src(), .{
            .horizontal_bar = .hide,
            .vertical_bar = .show,
            .scroll_info = &self.hsi,
            .frame_viewport = .{ .x = self.frame_viewport.x },
        }, .{
            .name = "GridWidgetHeaderScrollArea",
            .expand = .horizontal,
            .min_size_content = .{
                .h = self.header_height,
                .w = sumSlice(self.col_widths[0..]),
            },
        });
        self.hscroll.?.install();
    }

    // Any scroll-wheel events in the header should be applied to the body instead.
    const events = dvui.events();
    for (events) |*e| {
        if (e.evt == .mouse and dvui.eventMatchSimple(e, self.hscroll.?.data())) {
            const me = e.evt.mouse;
            if (me.action == .wheel_y) {
                self.bsi.scrollByOffset(.vertical, -me.action.wheel_y);
            } else if (me.action == .wheel_x) {
                self.bsi.scrollByOffset(.horizontal, me.action.wheel_x);
            }
        }
    }

    //    const w: f32, const expand: ?Options.Expand = width: {
    //        // Take width from col_opts if it is set.
    //        if (self.init_opts.col_widths) |col_info| {
    //            if (col_num < col_info.len) {
    //                break :width .{ col_info[col_num], null };
    //            } else {
    //                dvui.log.debug("GridWidget {x} has more columns than set in init_opts.col_widths. Using default column width of {d}\n", .{ self.data().id, default_col_width });
    //                break :width .{ default_col_width, null };
    //            }
    //        } else {
    //            if (opts.width) |w| {
    //                if (w > 0) {
    //                    break :width .{ w, null };
    //                } else {
    //                    dvui.log.debug("GridWidget {x} invalid opts.width provided to column(). Using default column width of {d}\n", .{ self.data().id, default_col_width });
    //                    break :width .{ default_col_width, null };
    //                }
    //            } else {
    //                // If there is no width specified either in col_info or col_opts,
    //                // just expand to fill available width.
    //                break :width .{ 0, .horizontal };
    //            }
    //        }
    //    };
    //    _ = expand;
    //    _ = w;
}

pub fn bodyScrollContainerCreate(self: *GridWidget, src: std.builtin.SourceLocation, col_num: usize) void {
    self.max_col = @max(self.max_col, col_num);
    if (self.hscroll) |*hscroll| {
        hscroll.deinit();
        self.hscroll = null;
    }

    if (self.bscroll == null) {
        self.bscroll = ScrollContainerWidget.init(
            src,
            self.bsi,
            .{ .frame_viewport = self.frame_viewport },
            .{
                .name = "GridWidgetScrollContainer",
            },
        ); // TODO:

        self.bscroll.?.install();
        self.bscroll.?.processEvents();
        self.bscroll.?.processVelocity();
        // Use this box to set the size of the scrollable area. Not sure why min/max size content on the scroll area doesn't work?
        const w = sumSlice(self.col_widths[0..]);
        self.bbox = BoxWidget.init(
            @src(),
            .{ .dir = .horizontal },
            .{
                .min_size_content = .{ .h = self.last_height, .w = w },
                .max_size_content = .{ .h = self.last_height, .w = w },
                .expand = .both,
            },
        );
        self.bbox.install();
    }

    //    const w: f32, const expand: ?Options.Expand = width: {
    //        // Take width from col_opts if it is set.
    //        if (self.init_opts.col_widths) |col_info| {
    //            if (col_num < col_info.len) {
    //                break :width .{ col_info[col_num], null };
    //            } else {
    //                dvui.log.debug("GridWidget {x} has more columns than set in init_opts.col_widths. Using default column width of {d}\n", .{ self.data().id, default_col_width });
    //                break :width .{ default_col_width, null };
    //            }
    //        } else {
    //            if (opts.width) |w| {
    //                if (w > 0) {
    //                    break :width .{ w, null };
    //                } else {
    //                    dvui.log.debug("GridWidget {x} invalid opts.width provided to column(). Using default column width of {d}\n", .{ self.data().id, default_col_width });
    //                    break :width .{ default_col_width, null };
    //                }
    //            } else {
    //                // If there is no width specified either in col_info or col_opts,
    //                // just expand to fill available width.
    //                break :width .{ 0, .horizontal };
    //            }
    //        }
    //    };
    //    _ = w;
    //    _ = expand;
}

pub fn headerCell(self: *GridWidget, src: std.builtin.SourceLocation, col_num: usize, opts: CellOptions) *BoxWidget {
    //const parent_rect = self.scroll.data().contentRect();
    // TODO: check col_num is valid
    self.extendColIfRequired(col_num); // TODO: This should do max_col as well.
    self.max_col = @max(self.max_col, col_num);

    if (self.hscroll == null) {
        if (self.bscroll != null) {
            dvui.log.debug("GridWidget {x} all header cells must be created before any body cells. Header will be placed in body.\n", .{self.data().id});
        } else {
            self.headerScrollAreaCreate(col_num);
        }
    }

    if (opts.width() > 0) {
        self.col_widths[col_num] = opts.width(); // TODO: This will prob end up being @max and using the same resizing rules as for rows?
    }

    const header_height: f32 = height: {
        if (opts.height() > 0) {
            break :height opts.height();
        } else {
            break :height if (self.resizing) 0 else self.header_height;
        }
    };
    var cell_opts = opts.toOptions();
    const xpos = sumSlice(self.col_widths[0..col_num]);
    cell_opts.rect = .{ .x = xpos, .y = 0, .w = self.col_widths[col_num], .h = header_height };

    // Create the cell and install as parent.
    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    cell.install();
    cell.drawBackground();

    // Determine heights for next frame.
    if (cell.data().contentRect().h > 0) {
        const height = cell.data().rect.h;
        self.header_height = @max(self.header_height, height);
    }
    return cell;
}

pub fn sumSlice(slice: anytype) @TypeOf(slice[0]) {
    var total: @TypeOf(slice[0]) = 0;
    for (slice) |item| {
        total += item;
    }
    return total;
}

pub fn bodyCell(self: *GridWidget, src: std.builtin.SourceLocation, col_num: usize, row_num: usize, opts: CellOptions) *BoxWidget {
    self.extendColIfRequired(col_num); // TODO: This should do max_col as well?
    self.max_col = @max(self.max_col, col_num);
    self.max_row = @max(self.max_row, row_num);
    if (self.bscroll == null) {
        self.bodyScrollContainerCreate(src, col_num);
    }
    if (opts.width() > 0) {
        self.col_widths[col_num] = opts.width(); // TODO: This will prob end up being @max and using the same resizing rules as for rows?
    }

    const cell_height: f32 = height: {
        if (opts.height() > 0) {
            break :height opts.height();
        } else {
            break :height if (self.resizing) 0 else self.row_height;
        }
    };

    const xpos = sumSlice(self.col_widths[0..col_num]);
    var cell_opts = opts.toOptions();
    const row_num_f: f32 = @floatFromInt(row_num);
    // TODO: This doesn't work for variable sized-rows. It needs to either be sequential using next_row_y or based on row_heights.
    cell_opts.rect = .{ .x = xpos, .y = row_num_f * self.row_height, .w = self.col_widths[col_num], .h = cell_height };

    // To support being called in a loop, combine col and row numbers as id_extra.
    // 9_223_372_036_854_775K cols should be enough for anyone.
    cell_opts.id_extra = (col_num << @bitSizeOf(usize) / 2) | row_num;

    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    cell.install();
    cell.drawBackground();
    if (cell.data().contentRect().h > 0) {
        const measured_cell_height = cell.data().rect.h;
        self.row_height = @max(self.row_height, measured_cell_height);
    }
    // If user provided a height, use that to position the next row, otherwise use the
    // calculated row_height.
    //self.next_row_y += opts.height orelse self.row_height;

    return cell;
}

/// Set the starting y value to begin rendering rows.
/// Used for setting the y location of the first row when virtual scrolling.
pub fn offsetRowsBy(self: *GridWidget, offset: f32) void {
    self.rows_y_offset = offset;
}

/// Converts a physical point (e.g. a mouse position) into a logical point
/// relative to the top-left of the grid's body.
/// Return the logical point if it is located within the grid body,
/// otherwise return null.
pub fn pointToBodyRelative(self: *GridWidget, point: Point.Physical) ?Point {
    const scroll_wd = self.scroll.data();
    var result = scroll_wd.rectScale().pointFromPhysical(point);
    if (scroll_wd.rect.contains(result) and result.y >= self.header_height) {
        result.y -= self.header_height;
        return result;
    }
    return null;
}

/// Set the grid's sort order when manually managing column sorting.
pub fn colSortSet(self: *GridWidget, col_num: usize, dir: SortDirection) void {
    self.sort_col_number = col_num;
    self.sort_direction = dir;
}

/// For automatic management of sort order, this must be called whenever
/// the sort order for any column has changed.
pub fn sortChanged(self: *GridWidget, col_num: usize) void {
    // If sorting on a new column, change current sort column to unsorted.
    if (col_num != self.sort_col_number) {
        self.sort_direction = .unsorted;
        self.sort_col_number = col_num;
    }
    // If new sort column, then ascending, otherwise opposite of current sort.
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
}

/// Returns the sort order for the current column.
pub fn colSortOrder(self: *const GridWidget, col_num: usize) SortDirection {
    if (col_num == self.sort_col_number) {
        return self.sort_direction;
    } else {
        return .unsorted;
    }
}

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed as an init_option
/// to the GridBodyWidget.
/// Note: Requires that all rows are the same height for the entire grid, including rows
/// not yet displayed. It is highly recommended to supply row heights to each cell
/// when using the virtual scroller.
pub const VirtualScroller = struct {
    pub const InitOpts = struct {
        // Total number of rows in the underlying dataset
        total_rows: usize,
        scroll_info: *ScrollInfo,
    };
    grid: *GridWidget,
    si: *ScrollInfo,
    total_rows: usize,
    pub fn init(grid: *GridWidget, init_opts: VirtualScroller.InitOpts) VirtualScroller {
        const si = init_opts.scroll_info;
        const total_rows_f: f32 = @floatFromInt(init_opts.total_rows);
        // Adding some tiny padding helps make sure the last row is displayed with very large virtual scroll sizes.
        // The actual padding required would depend on the row height, but this should help for normal text height grids.
        const end_padding = total_rows_f / 100_000;
        si.virtual_size.h = @max(total_rows_f * grid.row_height + scrollbar_padding_defaults.h + end_padding, si.viewport.h);

        const first_row: f32 = @floatFromInt(_startRow(grid, si, init_opts.total_rows));
        grid.offsetRowsBy(first_row * grid.row_height);
        return .{
            .grid = grid,
            .si = si,
            .total_rows = init_opts.total_rows,
        };
    }

    fn _startRow(grid: *const GridWidget, si: *ScrollInfo, total_rows: usize) usize {
        if (grid.row_height < 1) {
            return 0;
        }
        const first_row_in_viewport: usize = @intFromFloat(@round(si.viewport.y / grid.row_height));
        if (first_row_in_viewport == 0) {
            return 0;
        }
        return @min(first_row_in_viewport - 1, total_rows);
    }
    /// Return the first row to render (inclusive)
    pub fn startRow(self: *const VirtualScroller) usize {
        return _startRow(self.grid, self.si, self.total_rows);
    }

    /// Return the end row to render (exclusive)
    /// Can be used as slice[startRow()..endRow()]
    pub fn endRow(self: *const VirtualScroller) usize {
        const last_row_in_viewport: usize =
            if (self.grid.row_height < 1)
                0
            else
                @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.grid.row_height));
        return @min(last_row_in_viewport + 1, self.total_rows);
    }
};

/// Provides a draggable separator between columns
/// size must be a pointer into the same col_widths slice
/// passed to the GridWidget init_option.
pub const HeaderResizeWidget = struct {
    pub const InitOptions = struct {
        // Input and output width (.vertical) or height (.horizontal)
        size: *f32,
        // clicking on these extra pixels before/after (.vertical)
        // or above/below (.horizontal) the handle also counts
        // as clicking on the handle.
        grab_tolerance: f32 = 5,
        // Will not resize to less than this value
        min_size: ?f32 = null,
        // Will not resize to more than this value
        max_size: ?f32 = null,

        pub const fixed: ?InitOptions = null;
    };

    const defaults: Options = .{
        .name = "GridHeaderResize",
        .background = true, // TODO: remove this when border and background are no longer coupled
        .color_fill = .{ .name = .border },
        .min_size_content = .{ .w = 1, .h = 1 },
    };

    wd: WidgetData = undefined,
    direction: Direction = undefined,
    init_opts: InitOptions = undefined,
    // When user drags less than min_size or more than max_size
    // this offset is used to make them return the mouse back
    // to the min/max size before resizing can start again.
    offset: Point = .{},

    pub fn init(src: std.builtin.SourceLocation, dir: Direction, init_options: InitOptions, opts: Options) HeaderResizeWidget {
        var self = HeaderResizeWidget{};

        var widget_opts = HeaderResizeWidget.defaults.override(opts);
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

    pub fn install(self: *HeaderResizeWidget) void {
        self.wd.register();
        self.wd.borderAndBackground(.{});
    }

    pub fn matchEvent(self: *HeaderResizeWidget, e: *Event) bool {
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

    pub fn processEvents(self: *HeaderResizeWidget) void {
        const evts = dvui.events();
        for (evts) |*e| {
            if (!self.matchEvent(e))
                continue;

            self.processEvent(e, false);
        }
    }

    pub fn data(self: *HeaderResizeWidget) *WidgetData {
        return &self.wd;
    }

    pub fn processEvent(self: *HeaderResizeWidget, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.evt == .mouse) {
            const rs = self.wd.rectScale();
            const cursor: Cursor = switch (self.direction) {
                .vertical => .arrow_w_e,
                .horizontal => .arrow_n_s,
            };

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
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    dvui.refresh(null, @src(), self.wd.id);
                    switch (self.direction) {
                        .vertical => {
                            const unclamped_width = self.init_opts.size.* + dps.x / rs.s + self.offset.x;
                            self.init_opts.size.* = std.math.clamp(
                                unclamped_width,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.x = unclamped_width - self.init_opts.size.*;
                        },
                        .horizontal => {
                            const unclamped_height = self.init_opts.size.* + dps.y / rs.s + self.offset.y;
                            self.init_opts.size.* = std.math.clamp(
                                unclamped_height,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.y = unclamped_height - self.init_opts.size.*;
                        },
                    }
                }
            } else if (e.evt.mouse.action == .position) {
                dvui.cursorSet(cursor);
            }
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *HeaderResizeWidget) void {
        dvui.dataSet(null, self.wd.id, "_offset", self.offset);
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        self.* = undefined;
    }
};
test {
    @import("std").testing.refAllDecls(@This());
}
