const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");
comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
var scale_val: f32 = 1.0;

var g_backend: ?SDLBackend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try SDLBackend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
    highlighting.deinit(gpa);
}

var highlighting: std.ArrayList(TokenHighlight) = .empty;

const TokenHighlight = struct {
    tok: Token,
    color: dvui.Color,
};

// both dvui and SDL drawing
// return false if user wants to exit the app
fn gui_frame() bool {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }

            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return false;
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();
    if (!tokenzied) {
        // Tokenize the code only once
        var tokenizer: Tokenizer = .init(src_code);
        var token: Token = tokenizer.next();
        while (token.tag != .eof) : (token = tokenizer.next()) {
            highlighting.append(gpa, .{ .tok = token, .color = colours.get(token.tag) }) catch |err| @panic(@errorName(err));
        }
        highlighting.append(gpa, .{ .tok = token, .color = colours.get(token.tag) }) catch |err| @panic(@errorName(err));
        tokenzied = true;
        std.debug.print("We got {d} tokens.\n", .{highlighting.items.len});
    }

    var text = dvui.textLayout(@src(), .{}, .{ .expand = .both });
    defer text.deinit();
    var src_pos: usize = 0;
    for (highlighting.items) |highlight| {
        // Check if there is text that is not tokenized (comments / whitespace etc)
        if (src_pos < highlight.tok.loc.start) {
            // If it is a '//' comment, color it appropriately.
            const non_tok_color = if (std.mem.indexOf(u8, src_code[src_pos..highlight.tok.loc.start], "//") != null) color_comment else dvui.Color.white;

            // Skip any '\r' chars and display the non-tokenized text.
            while (std.mem.indexOf(u8, src_code[src_pos..highlight.tok.loc.start], "\r")) |index| {
                text.addText(src_code[src_pos .. src_pos + index], .{ .color_text = non_tok_color });
                src_pos += index + 1;
            }
            text.addText(src_code[src_pos..highlight.tok.loc.start], .{ .color_text = non_tok_color });
        }
        // Display the tokenized text in the token color.
        text.addText(src_code[highlight.tok.loc.start..highlight.tok.loc.end], .{ .color_text = highlight.color });
        src_pos = highlight.tok.loc.end;
    }

    return true;
}

var tokenzied: bool = false;

const color_keyword: dvui.Color = .fromHex("#569CD6");
const color_identifier: dvui.Color = .fromHex("#4EC9B0");
const color_builtin: dvui.Color = .fromHex("#DCDCAA");
const color_string: dvui.Color = .fromHex("#CE9178");
const color_operator: dvui.Color = .fromHex("#D4D4D4");
const color_braces: dvui.Color = .fromHex("#CCCCCC");
const color_punctuation: dvui.Color = .fromHex("#CCCCCC");
const color_comment: dvui.Color = .fromHex("#6A9955");
const color_constant: dvui.Color = .fromHex("#B5CEA8");

const colours: std.EnumArray(Token.Tag, dvui.Color) = .init(.{
    .invalid = .red,
    .invalid_periodasterisks = .red,
    .identifier = color_identifier,
    .string_literal = color_string,
    .multiline_string_literal_line = color_string,
    .char_literal = color_string,
    .eof = .white,
    .builtin = color_builtin,
    .bang = color_operator,
    .pipe = color_operator,
    .pipe_pipe = color_operator,
    .pipe_equal = color_operator,
    .equal = color_operator,
    .equal_equal = color_operator,
    .equal_angle_bracket_right = color_braces,
    .bang_equal = color_operator,
    .l_paren = color_braces,
    .r_paren = color_braces,
    .semicolon = color_punctuation,
    .percent = color_operator,
    .percent_equal = color_operator,
    .l_brace = color_braces,
    .r_brace = color_braces,
    .l_bracket = color_braces,
    .r_bracket = color_braces,
    .period = color_operator,
    .period_asterisk = color_operator,
    .ellipsis2 = color_braces,
    .ellipsis3 = color_braces,
    .caret = color_operator,
    .caret_equal = color_operator,
    .plus = color_operator,
    .plus_plus = color_operator,
    .plus_equal = color_operator,
    .plus_percent = color_operator,
    .plus_percent_equal = color_operator,
    .plus_pipe = color_operator,
    .plus_pipe_equal = color_operator,
    .minus = color_operator,
    .minus_equal = color_operator,
    .minus_percent = color_operator,
    .minus_percent_equal = color_operator,
    .minus_pipe = color_operator,
    .minus_pipe_equal = color_operator,
    .asterisk = color_operator,
    .asterisk_equal = color_operator,
    .asterisk_asterisk = color_operator,
    .asterisk_percent = color_operator,
    .asterisk_percent_equal = color_operator,
    .asterisk_pipe = color_operator,
    .asterisk_pipe_equal = color_operator,
    .arrow = color_operator,
    .colon = color_keyword,
    .slash = color_operator,
    .slash_equal = color_operator,
    .comma = color_punctuation,
    .ampersand = color_operator,
    .ampersand_equal = color_operator,
    .question_mark = color_operator,
    .angle_bracket_left = color_operator,
    .angle_bracket_left_equal = color_operator,
    .angle_bracket_angle_bracket_left = color_operator,
    .angle_bracket_angle_bracket_left_equal = color_operator,
    .angle_bracket_angle_bracket_left_pipe = color_operator,
    .angle_bracket_angle_bracket_left_pipe_equal = color_operator,
    .angle_bracket_right = color_operator,
    .angle_bracket_right_equal = color_operator,
    .angle_bracket_angle_bracket_right = color_operator,
    .angle_bracket_angle_bracket_right_equal = color_operator,
    .tilde = color_operator,
    .number_literal = color_constant,
    .doc_comment = color_comment,
    .container_doc_comment = color_comment,
    .keyword_addrspace = color_keyword,
    .keyword_align = color_keyword,
    .keyword_allowzero = color_keyword,
    .keyword_and = color_keyword,
    .keyword_anyframe = color_keyword,
    .keyword_anytype = color_keyword,
    .keyword_asm = color_keyword,
    .keyword_break = color_keyword,
    .keyword_callconv = color_keyword,
    .keyword_catch = color_keyword,
    .keyword_comptime = color_keyword,
    .keyword_const = color_keyword,
    .keyword_continue = color_keyword,
    .keyword_defer = color_keyword,
    .keyword_else = color_keyword,
    .keyword_enum = color_keyword,
    .keyword_errdefer = color_keyword,
    .keyword_error = color_keyword,
    .keyword_export = color_keyword,
    .keyword_extern = color_keyword,
    .keyword_fn = color_keyword,
    .keyword_for = color_keyword,
    .keyword_if = color_keyword,
    .keyword_inline = color_keyword,
    .keyword_noalias = color_keyword,
    .keyword_noinline = color_keyword,
    .keyword_nosuspend = color_keyword,
    .keyword_opaque = color_keyword,
    .keyword_or = color_keyword,
    .keyword_orelse = color_keyword,
    .keyword_packed = color_keyword,
    .keyword_pub = color_keyword,
    .keyword_resume = color_keyword,
    .keyword_return = color_keyword,
    .keyword_linksection = color_keyword,
    .keyword_struct = color_keyword,
    .keyword_suspend = color_keyword,
    .keyword_switch = color_keyword,
    .keyword_test = color_keyword,
    .keyword_threadlocal = color_keyword,
    .keyword_try = color_keyword,
    .keyword_union = color_keyword,
    .keyword_unreachable = color_keyword,
    .keyword_var = color_keyword,
    .keyword_volatile = color_keyword,
    .keyword_while = color_keyword,
});

const Tokenizer = std.zig.Tokenizer;
const Token = std.zig.Token;
const src_code = @embedFile("sdl-editor.zig");
// this is a end of file comment. This should now get picked up
