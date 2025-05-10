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

pub const InitOpts = ScrollAreaWidget.InitOpts;

const ColWidth = struct {
    const RowType = enum { header, body };
    // Width of the header and body columns
    w: f32,
    last_updated_by: RowType,
    // When col width is set by a header/body, ignore the next update from the body/header as its
    // width will be 1 frame behind
    ignore_next_update: bool,
    // If width is controlled by header/body, then updates all from body/header are ignored.
    // This is set when the header is styled to expand horizontally or has a fixed width.
    controlled_by: ?RowType,
};

vbox: BoxWidget = undefined,
hbox: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined,
init_opts: InitOpts = undefined,
num_cols: f32 = undefined,
current_col: ?BoxWidget = null,
current_cell: ?BoxWidget = null,
next_row_y: f32 = 0,
last_height: f32 = 0,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);
    if (dvui.dataGet(null, self.data().id, "_last_height", f32)) |last_height| {
        self.last_height = last_height;
    }
    // TODO: Assumes a scroll_info
    //self.init_opts.scroll_info.?.virtual_size.h = @max(self.last_height, self.init_opts.scroll_info.?.viewport.h);
    //std.debug.print("Viewport h = {d}, last_h = {d}\n", .{ self.init_opts.scroll_info.?.virtual_size.h, self.last_height });

    //    self.options = options;
    return self;
}

pub fn install(self: *GridWidget) !void {
    try self.vbox.install();
    try self.vbox.drawBackground();

    self.scroll = ScrollAreaWidget.init(@src(), self.init_opts, .{ .expand = .both });
    try self.scroll.install();

    // Lay out columns horizontally.
    self.hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .both });
    try self.hbox.install();
    try self.hbox.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    dvui.dataSet(null, self.data().id, "_last_height", self.next_row_y);
    self.hbox.deinit();
    self.scroll.deinit();
    self.vbox.deinit();
}

pub fn colBegin(self: *GridWidget, src: std.builtin.SourceLocation, col_width: f32) !void {
    // TODO: Should this take styling options?
    // TODO: Check current col is null or else error.
    self.current_col = BoxWidget.init(src, .vertical, false, .{
        .expand = .vertical,
        .min_size_content = .{ .w = col_width, .h = self.last_height },
        .max_size_content = .width(col_width),
        .border = Rect.all(1),
        .color_border = .{ .color = try dvui.Color.fromHex("#ff0000".*) },
    });
    try self.current_col.?.install();
    try self.current_col.?.drawBackground();
    self.next_row_y = 0;
}

pub fn colEnd(self: *GridWidget) void {
    if (self.current_col) |*current_col| {
        std.debug.print("Current Col = {}\n", .{current_col.data().rect});
        current_col.deinit();
        self.current_col = null;
    } else {
        // TODO: Some sort of error.
    }
    std.debug.print("Scroll info = {}\n", .{self.scroll.si});
}

pub fn headerCellBegin(self: *GridWidget, src: std.builtin.SourceLocation, opts: dvui.Options) !void {
    // TODO: Safety checks
    _ = opts; // TODO: Chose which opts to take.
    const y = self.scroll.si.viewport.y - 1.0;
    const parent_rect = self.current_col.?.data().backgroundRect();

    self.current_cell = BoxWidget.init(src, .horizontal, false, .{
        .expand = .horizontal,
        .rect = .{ .x = parent_rect.x, .y = y, .w = parent_rect.w },
        .color_fill = .{ .name = .fill_window },
        //        .margin = Rect.all(0),
        //        .padding = Rect.all(0),
        .background = true,
        .border = Rect.all(1),
        .color_border = .{ .color = try dvui.Color.fromHex("#0000ff".*) },
    });
    try self.current_cell.?.install();
    try self.current_cell.?.drawBackground(); // TODO: These background draws prob not required?
}

pub fn headerCellEnd(self: *GridWidget) void {
    if (self.current_cell) |*current_cell| {
        self.next_row_y += current_cell.data().rect.h;
        current_cell.deinit();
        self.current_cell = null;
    }
}

pub fn bodyCellBegin(self: *GridWidget, src: std.builtin.SourceLocation, row_num: usize, opts: dvui.Options) !void {
    // TODO: Safety checks
    _ = opts; // TODO: Chose which opts to take.
    const parent_rect = self.current_col.?.data().contentRect();

    self.current_cell = BoxWidget.init(src, .horizontal, false, .{
        .id_extra = row_num,
        .expand = .horizontal,
        .rect = .{ .x = parent_rect.x, .y = self.next_row_y, .w = parent_rect.w },
    });
    try self.current_cell.?.install();
    try self.current_cell.?.drawBackground(); // TODO: These background draws prob not required?
}

pub fn bodyCellEnd(self: *GridWidget) void {
    if (self.current_cell) |*current_cell| {
        self.next_row_y += current_cell.data().rect.h;
        current_cell.deinit();
        self.current_cell = null;
    }
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};

    // Sort direction for a column
    pub const SortDirection = enum {
        unsorted,
        ascending,
        descending,
    };

    pub var defaults: Options = .{
        .name = "GridHeaderWidget",
        // generally the top of a scroll area is against something flat (like
        // window header), and the bottom is against something curved (bottom
        // of a window)
    };

    hbox: BoxWidget = undefined,
    header_hbox: BoxWidget = undefined,
    header_scroll: ScrollAreaWidget = undefined,
    scroll_padding: BoxWidget = undefined,
    col_hbox: ?BoxWidget = null,
    grid: *GridWidget = undefined,
    col_number: usize = 0,
    sort_col_number: usize = 0,
    sort_direction: SortDirection = .unsorted,
    height: f32 = 0,
    height_this_frame: f32 = 0,
    si: ScrollInfo = .{ .horizontal = .given, .vertical = .none },

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        var self = GridHeaderWidget{};
        const options = GridHeaderWidget.defaults.override(opts);

        _ = init_opts;
        self.grid = grid;
        self.hbox = BoxWidget.init(src, .horizontal, false, options.override(.{ .expand = .horizontal }));

        if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
            self.sort_col_number = sort_col;
        }
        if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
            self.sort_direction = sort_direction;
        }
        if (dvui.dataGet(null, self.data().id, "_height", f32)) |height| {
            self.height = height;
        }
        if (dvui.dataGet(null, self.data().id, "_si", ScrollInfo)) |*si| {
            self.si = si.*;
        }

        return self;
    }

    pub fn deinit(self: *GridHeaderWidget) void {
        self.header_hbox.deinit();
        self.header_scroll.deinit();

        dvui.dataSet(null, self.data().id, "_height", self.height_this_frame);
        dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
        dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);
        dvui.dataSet(null, self.data().id, "_si", self.si);
        self.hbox.deinit();
    }

    pub fn install(self: *GridHeaderWidget) !void {
        try self.hbox.install();
        try self.hbox.drawBackground();
        self.scroll_padding = BoxWidget.init(@src(), .vertical, false, .{
            .min_size_content = .{ .w = 10 }, // TODO: 10 = scroll bar widget width
            .expand = .vertical,
            .gravity_x = 1.0,
            .border = Rect.all(0),
        });
        try self.scroll_padding.install();
        try self.scroll_padding.drawBackground();
        self.scroll_padding.deinit();

        self.si.virtual_size.w = self.grid.si.virtual_size.w + 10; // TODO: 10 = scroll bar widget width
        self.si.virtual_size.h = self.grid.si.viewport.h;
        self.si.viewport.x = self.grid.si.viewport.x;
        self.header_scroll = ScrollAreaWidget.init(@src(), .{ .scroll_info = &self.si, .horizontal_bar = .hide, .vertical_bar = .hide }, .{ .expand = .horizontal });
        try self.header_scroll.install();
        self.header_hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .horizontal });
        try self.header_hbox.install();
        try self.header_hbox.drawBackground();
    }

    pub fn data(self: *GridHeaderWidget) *WidgetData {
        return self.hbox.data();
    }

    /// Start a new column heading.
    /// must be called before any widgets are created.
    pub fn colBegin(self: *GridHeaderWidget, src: std.builtin.SourceLocation, opts: Options) !void {
        const col_options: Options = .{
            //  .border = Rect.all(1),
            .min_size_content = opts.min_size_content,
            .max_size_content = opts.max_size_content,
        };
        if (self.col_number == 99) {
            std.debug.print("HEADER Col opts = {}\n", .{col_options});
        }

        self.col_hbox = BoxWidget.init(src, .horizontal, false, col_options);
        try self.col_hbox.?.install();
        try self.col_hbox.?.drawBackground();
    }

    /// End of a column heading.
    /// must be called after all column widgets are deinit-ed.
    pub fn colEnd(self: *GridHeaderWidget) void {
        // Check in_body, log warning if not?? Needed?
        if (self.col_hbox) |*hbox| {
            const header_width = hbox.data().contentRect().w;
            const header_height = hbox.data().contentRect().h;

            const control_width = switch (hbox.data().options.expand orelse .none) {
                .horizontal, .both, .ratio => true,
                else => false,
            };
            self.grid.colWidthReport(.header, header_width, self.col_number, control_width) catch {}; // Don't want to throw from a deinit.

            if (header_height > self.height_this_frame) {
                self.height_this_frame = header_height;
            }

            hbox.deinit();
            self.col_hbox = null;
        } // else log warning.

        self.col_number += 1;
    }

    /// Must be called from the column header when the current column's sort order has changed.
    pub fn sortChanged(self: *GridHeaderWidget) void {
        // If sorting on a new column, change current sort column to unsorted.
        if (self.col_number != self.sort_col_number) {
            self.sort_direction = .unsorted;
            self.sort_col_number = self.col_number;
        }
        // If new sort column, then ascending, otherwise opposite of current sort.
        self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
    }

    /// Returns the sort order for the current header.
    pub fn colSortOrder(self: *const GridHeaderWidget) SortDirection {
        if (self.col_number == self.sort_col_number) {
            return self.sort_direction;
        } else {
            return .unsorted;
        }
    }
};

pub const GridBodyWidget = struct {
    pub const defaults: Options = .{
        .name = "GridBodyWidget",
        .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
        // Must either provide .expand or .min_size_content for virtual scrolling to work.
        .expand = .vertical,
    };
    pub const InitOpts = struct {};

    grid: *GridWidget = undefined,
    scroll: ScrollAreaWidget = undefined,
    hbox: BoxWidget = undefined,
    col_vbox: ?BoxWidget = null,
    row_hbox: ?BoxWidget = null,
    col_number: usize = 0,
    cell_number: usize = 0,
    // invisible_height is used to pad the top of the scroll area in virtual scrolling mode
    // The padded area will contain the "invisibile" rows at the start of the grid.
    invisible_height: f32 = 0,
    row_height: f32 = 0,
    row_height_this_frame: f32 = 0,
    min_size: ?Size = null,
    max_size: ?MaxSize = null,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridBodyWidget.InitOpts, opts: Options) GridBodyWidget {
        var self = GridBodyWidget{};
        const options = GridBodyWidget.defaults.override(opts);
        _ = init_opts;

        self.grid = grid;
        self.scroll = ScrollAreaWidget.init(src, self.grid.init_opts, options);

        if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
            self.row_height = row_height;
        }
        self.min_size = opts.min_size_content;
        self.max_size = opts.max_size_content;

        return self;
    }

    pub fn install(self: *GridBodyWidget) !void {
        try self.scroll.install();
        self.hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .vertical });

        try self.hbox.install();
        try self.hbox.drawBackground();
    }

    pub fn deinit(self: *GridBodyWidget) void {
        dvui.dataSet(null, self.data().id, "_row_height", if (self.row_height_this_frame > 0) self.row_height_this_frame else self.row_height);
        self.hbox.deinit();
        self.scroll.deinit();
    }

    pub fn data(self: *GridBodyWidget) *WidgetData {
        return self.scroll.data();
    }

    /// Begin a new grid column
    /// must be called before any widgets are created in the column
    pub fn colBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation, opts: Options) !void {

        // TODO: Check if box is null. Log warning if not.
        //const min_width = self.grid.colMinWidthGet(.body, self.col_number);
        //const max_width = self.grid.colMaxWidthGet(.body, self.col_number);
        //if (self.col_number == 99) {
        //    std.debug.print("BODYMin width = {d}, max_width = {d}\n", .{ min_width, max_width orelse 0 });
        //}

        //        var col_options: Options = .{
        //            .min_size_content = .{ .w = min_width },
        //            .max_size_content = if (max_width) |mw| .width(mw) else opts.max_size_content,
        //            .border = Rect.all(1),
        //        };
        //        if (opts.min_size_content) |min_size_content| {
        //            col_options.min_size_content = min_size_content;
        //        }
        const col_options: Options = .{
            //.border = Rect.all(1),
            .min_size_content = opts.min_size_content,
            .max_size_content = opts.max_size_content,
        };

        if (self.col_number == 99) {
            std.debug.print("BODY Col opts = {}\n", .{col_options});
        }
        self.col_vbox = BoxWidget.init(src, .vertical, false, col_options);
        try self.col_vbox.?.install();
        try self.col_vbox.?.drawBackground();

        // Create a vbox to pad out space for any invisible rows.
        if (self.invisible_height > 0) {
            var vbox = BoxWidget.init(src, .vertical, false, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = self.invisible_height },
                .max_size_content = .height(self.invisible_height),
            });
            try vbox.install();
            vbox.deinit();
        }
    }

    /// End a new column
    /// must be called after all widgets in the column have been deinit-ed.
    pub fn colEnd(self: *GridBodyWidget) void {
        if (self.col_vbox) |*vbox| {
            const current_width = vbox.data().contentRect().w;
            self.grid.colWidthReport(.body, current_width, self.col_number, false) catch {}; // Don't want to throw from a deinit.

            vbox.deinit();
            self.col_vbox = null;
        } // else log warning.
        self.col_number += 1;
    }

    // Start a new cell.
    // must be called before any widgets are created in the cell
    pub fn cellBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation) !void {
        self.row_hbox = BoxWidget.init(src, .horizontal, false, .{ .id_extra = self.cell_number, .expand = .both });
        try self.row_hbox.?.install();
        try self.row_hbox.?.drawBackground();
    }

    // End a new cell
    // must be called after all widgets in the cell have been deinit-ed.
    pub fn cellEnd(self: *GridBodyWidget) void {
        if (self.row_hbox) |*hbox| {
            if (hbox.wd.rect.h > self.row_height_this_frame) {
                self.row_height_this_frame = hbox.wd.rect.h;
            }
            hbox.deinit();
            self.row_hbox = null;
        }
        self.cell_number += 1;
    }

    pub fn virtualScroller(self: *GridBodyWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
        return GridVirtualScroller.init(self, init_opts);
    }
};

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
    body: *GridBodyWidget,
    si: *ScrollInfo,
    total_rows: usize,
    window_size: usize,
    pub fn init(body: *GridBodyWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
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
