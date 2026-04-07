const std = @import("std");
const ghostty_vt = @import("ghostty-vt");
const wuffs = @import("wuffs");

fn decodePng(alloc: std.mem.Allocator, data: []const u8) ghostty_vt.sys.DecodeError!ghostty_vt.sys.Image {
    const result = wuffs.png.decode(alloc, data) catch |err| switch (err) {
        error.WuffsError, error.Overflow => return error.InvalidData,
        error.OutOfMemory => return error.OutOfMemory,
    };
    return .{
        .width = result.width,
        .height = result.height,
        .data = result.data,
    };
}

pub fn main() !void {
    ghostty_vt.sys.decode_png = &decodePng;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Query the real terminal's size via stdout (still a tty even
    // when stdin is piped). This gives us cols, rows, and pixel
    // dimensions needed for kitty graphics cursor advancement.
    const ws = std.posix.system.winsize;
    var wsz: ws = undefined;
    const stdout_fd = std.fs.File.stdout().handle;
    const rc = std.posix.system.ioctl(stdout_fd, std.posix.system.T.IOCGWINSZ, @intFromPtr(&wsz));
    const cols: u16, const rows: u16, const width_px: u16, const height_px: u16 = if (rc == 0)
        .{ wsz.col, wsz.row, wsz.xpixel, wsz.ypixel }
    else
        .{ 150, 80, 0, 0 };

    // Create a terminal
    var t: ghostty_vt.Terminal = try .init(alloc, .{
        .cols = cols,
        .rows = rows,
        .kitty_image_loading_limits = .all,
    });
    t.width_px = width_px;
    t.height_px = height_px;
    defer t.deinit(alloc);

    // Create a read-only VT stream for parsing terminal sequences
    var stream = t.vtStream();
    defer stream.deinit();

    // Read from stdin
    const stdin = std.fs.File.stdin();
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try stdin.readAll(&buf);
        if (n == 0) break;

        // Replace \n with \r\n
        for (buf[0..n]) |byte| {
            if (byte == '\n') stream.next('\r');
            stream.next(byte);
        }
    }

    // Use TerminalFormatter to emit HTML
    var formatter: ghostty_vt.formatter.TerminalFormatter = .init(&t, .{
        .emit = .vt,
        .palette = &t.colors.palette.current,
    });
    formatter.extra.screen.kitty_graphics = true;

    // Write to stdout
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("{f}", .{formatter});
    try stdout.flush();
}
