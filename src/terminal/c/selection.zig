const std = @import("std");
const testing = std.testing;
const lib = @import("../lib.zig");
const CAllocator = lib.alloc.Allocator;
const terminal_c = @import("terminal.zig");
const ZigTerminal = @import("../Terminal.zig");
const Selection = @import("../Selection.zig");
const PageList = @import("../PageList.zig");
const point = @import("../point.zig");
const size = @import("../size.zig");
const Result = @import("result.zig").Result;

/// Set a selection on the terminal's active screen.
///
/// Creates a selection from `start` to `end` in the given coordinate
/// system. If `rectangle` is true the selection is rectangular (block
/// mode); otherwise it is a normal character-wise selection.
///
/// Any existing selection is replaced.
pub fn select(
    terminal_: terminal_c.Terminal,
    start: point.Point.C,
    end_pt: point.Point.C,
    rectangle: bool,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    const screen = t.screens.active;

    const start_zig: point.Point = switch (start.tag) {
        .active => .{ .active = start.value.active },
        .viewport => .{ .viewport = start.value.viewport },
        .screen => .{ .screen = start.value.screen },
        .history => .{ .history = start.value.history },
    };
    const end_zig: point.Point = switch (end_pt.tag) {
        .active => .{ .active = end_pt.value.active },
        .viewport => .{ .viewport = end_pt.value.viewport },
        .screen => .{ .screen = end_pt.value.screen },
        .history => .{ .history = end_pt.value.history },
    };

    const start_pin = screen.pages.pin(start_zig) orelse
        return .invalid_value;
    const end_pin = screen.pages.pin(end_zig) orelse
        return .invalid_value;

    const sel = Selection.init(start_pin, end_pin, rectangle);
    screen.select(sel) catch return .out_of_memory;

    return .success;
}

/// Clear the current selection on the terminal's active screen.
pub fn select_clear(
    terminal_: terminal_c.Terminal,
) callconv(lib.calling_conv) void {
    const t: *ZigTerminal = (terminal_ orelse return).terminal;
    t.screens.active.clearSelection();
}

/// Check whether the terminal's active screen has a selection.
pub fn has_selection(
    terminal_: terminal_c.Terminal,
    out: *bool,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    out.* = t.screens.active.selection != null;
    return .success;
}

/// Check whether the given point is contained within the current selection.
///
/// Returns `no_value` if there is no active selection.
pub fn selection_contains(
    terminal_: terminal_c.Terminal,
    pt: point.Point.C,
    out: *bool,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    const screen = t.screens.active;
    const sel = screen.selection orelse return .no_value;

    const zig_pt: point.Point = switch (pt.tag) {
        .active => .{ .active = pt.value.active },
        .viewport => .{ .viewport = pt.value.viewport },
        .screen => .{ .screen = pt.value.screen },
        .history => .{ .history = pt.value.history },
    };

    const pin = screen.pages.pin(zig_pt) orelse
        return .invalid_value;

    out.* = sel.contains(screen, pin);
    return .success;
}

/// Get the ordered top-left and bottom-right points of the current selection
/// in screen coordinates.
///
/// Returns `no_value` if there is no active selection.
pub fn selection_bounds(
    terminal_: terminal_c.Terminal,
    out_tl: ?*point.Coordinate,
    out_br: ?*point.Coordinate,
    out_rectangle: ?*bool,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    const screen = t.screens.active;
    const sel = screen.selection orelse return .no_value;

    const tl_pin = sel.topLeft(screen);
    const br_pin = sel.bottomRight(screen);

    if (out_tl) |tl| {
        const tl_pt = screen.pages.pointFromPin(.viewport, tl_pin) orelse
            return .invalid_value;
        tl.* = tl_pt.viewport;
    }
    if (out_br) |br| {
        const br_pt = screen.pages.pointFromPin(.viewport, br_pin) orelse
            return .invalid_value;
        br.* = br_pt.viewport;
    }
    if (out_rectangle) |rect| {
        rect.* = sel.rectangle;
    }

    return .success;
}

/// Extract the selected text as a UTF-8 string into a caller-provided buffer.
///
/// If `buf` is NULL or `buf_len` is too small, returns `out_of_space` and
/// sets `out_len` to the required buffer size. On success, `out_len` is
/// set to the number of bytes written (not including any terminator).
///
/// Returns `no_value` if there is no active selection.
pub fn selection_to_string(
    terminal_: terminal_c.Terminal,
    out_buf: ?[*]u8,
    buf_len: usize,
    out_len: *usize,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    const screen = t.screens.active;
    const sel = screen.selection orelse return .no_value;

    // Use a fixed-buffer writer first to try to write directly.
    var writer: std.Io.Writer = .fixed(if (out_buf) |buf|
        buf[0..buf_len]
    else
        &.{});

    const formatter_mod = @import("../formatter.zig");
    var formatter: formatter_mod.ScreenFormatter = .init(
        screen,
        .{
            .emit = .plain,
            .unwrap = true,
            .trim = true,
        },
    );
    formatter.content = .{ .selection = sel };

    formatter.format(&writer) catch |err| switch (err) {
        error.WriteFailed => {
            // Buffer too small — calculate the required size.
            var discarding: std.Io.Writer.Discarding = .init(&.{});
            formatter.format(&discarding.writer) catch unreachable;
            out_len.* = @intCast(discarding.count);
            return .out_of_space;
        },
    };

    out_len.* = writer.end;
    return .success;
}

/// Extract the selected text as a UTF-8 string, allocating the buffer.
///
/// The caller must free the returned buffer with `ghostty_free()` using
/// the same allocator (or NULL for the default).
///
/// Returns `no_value` if there is no active selection.
pub fn selection_to_string_alloc(
    terminal_: terminal_c.Terminal,
    alloc_: ?*const CAllocator,
    out_ptr: *?[*]u8,
    out_len: *usize,
) callconv(lib.calling_conv) Result {
    const t: *ZigTerminal = (terminal_ orelse return .invalid_value).terminal;
    const screen = t.screens.active;
    const sel = screen.selection orelse return .no_value;
    const alloc = lib.alloc.default(alloc_);

    const text = screen.selectionString(alloc, .{ .sel = sel }) catch
        return .out_of_memory;

    out_ptr.* = @constCast(text.ptr);
    out_len.* = text.len;
    return .success;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "select and has_selection" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    // No selection initially
    var has: bool = undefined;
    try testing.expectEqual(Result.success, has_selection(t, &has));
    try testing.expect(!has);

    // Write some text so the points are valid
    terminal_c.vt_write(t, "Hello, World!", 13);

    // Create a selection
    const start_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    const end_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 4, .y = 0 } },
    };
    try testing.expectEqual(Result.success, select(t, start_pt, end_pt, false));

    try testing.expectEqual(Result.success, has_selection(t, &has));
    try testing.expect(has);
}

test "select_clear" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    terminal_c.vt_write(t, "Hello", 5);

    const start_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    const end_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 4, .y = 0 } },
    };
    try testing.expectEqual(Result.success, select(t, start_pt, end_pt, false));

    var has: bool = undefined;
    try testing.expectEqual(Result.success, has_selection(t, &has));
    try testing.expect(has);

    select_clear(t);

    try testing.expectEqual(Result.success, has_selection(t, &has));
    try testing.expect(!has);
}

test "select_clear null terminal" {
    select_clear(null);
}

test "has_selection null terminal" {
    var has: bool = undefined;
    try testing.expectEqual(Result.invalid_value, has_selection(null, &has));
}

test "selection_contains" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    terminal_c.vt_write(t, "Hello, World!", 13);

    const start_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    const end_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 4, .y = 0 } },
    };
    try testing.expectEqual(Result.success, select(t, start_pt, end_pt, false));

    // Point inside selection
    var contained: bool = undefined;
    const inside = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 2, .y = 0 } },
    };
    try testing.expectEqual(Result.success, selection_contains(t, inside, &contained));
    try testing.expect(contained);

    // Point outside selection
    const outside = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 6, .y = 0 } },
    };
    try testing.expectEqual(Result.success, selection_contains(t, outside, &contained));
    try testing.expect(!contained);
}

test "selection_contains no selection" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    var contained: bool = undefined;
    const pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    try testing.expectEqual(Result.no_value, selection_contains(t, pt, &contained));
}

test "selection_to_string" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    terminal_c.vt_write(t, "Hello, World!", 13);

    const start_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    const end_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 4, .y = 0 } },
    };
    try testing.expectEqual(Result.success, select(t, start_pt, end_pt, false));

    // Query required size
    var required: usize = 0;
    try testing.expectEqual(Result.out_of_space, selection_to_string(t, null, 0, &required));
    try testing.expect(required > 0);

    // Extract into buffer
    var buf: [1024]u8 = undefined;
    var written: usize = 0;
    try testing.expectEqual(Result.success, selection_to_string(t, &buf, buf.len, &written));
    try testing.expectEqualStrings("Hello", buf[0..written]);
}

test "selection_to_string no selection" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    var len: usize = 0;
    try testing.expectEqual(Result.no_value, selection_to_string(t, null, 0, &len));
}

test "selection_to_string_alloc" {
    var t: terminal_c.Terminal = null;
    try testing.expectEqual(Result.success, terminal_c.new(
        &lib.alloc.test_allocator,
        &t,
        .{ .cols = 80, .rows = 24, .max_scrollback = 10_000 },
    ));
    defer terminal_c.free(t);

    terminal_c.vt_write(t, "Hello, World!", 13);

    const start_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 0, .y = 0 } },
    };
    const end_pt = point.Point.C{
        .tag = .active,
        .value = .{ .active = .{ .x = 4, .y = 0 } },
    };
    try testing.expectEqual(Result.success, select(t, start_pt, end_pt, false));

    var ptr: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(Result.success, selection_to_string_alloc(
        t,
        &lib.alloc.test_allocator,
        &ptr,
        &len,
    ));
    defer {
        const allocator = lib.alloc.default(&lib.alloc.test_allocator);
        allocator.free(ptr.?[0..len + 1]);
    }

    try testing.expectEqualStrings("Hello", ptr.?[0..len]);
}
