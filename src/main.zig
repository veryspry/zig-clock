const std = @import("std");
const assert = std.debug.assert;
const zig_clock = @import("zig_clock");

pub fn main() !void {
	var stdout_buffer: [1024]u8 = undefined;
	var stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    overrideSignals();

   	try displayAltBuffer(stdout);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    while (true) {
     	const winsize = try getWinSize(&stdout_file);

        try clearPrompt(stdout);
        const text = try std.fmt.allocPrint(allocator, "Rows: {}, Cols: {}\n", .{ winsize.row, winsize.col });
        try printCentered(stdout, text, winsize);
        defer allocator.free(text);  // Don't forget to free

    	// std.Thread.sleep(1_000_000_000);
    }
}

fn handleSigInt(_: c_int) callconv(.c) void {
	// TODO NOTHING (for now)
    // std.log.debug("SIGNAL {d}", .{sig_num});
}

fn overrideSignals() void {
	const action = std.posix.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &action, null);
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
    std.posix.sigaction(std.posix.SIG.USR1, &action, null);
}

fn clearPrompt(w: *std.io.Writer) !void {
	const clear_sequence = "\x1b[2J";
    try w.print("{s}", .{ clear_sequence });
    try w.flush();
}

fn displayAltBuffer(w: *std.io.Writer) !void {
	const alt_buf_sequence = "\x1B[?1049h";
    try w.print("{s}", .{ alt_buf_sequence });
    try w.flush();
}

fn displayMainBuffer(w: *std.io.Writer) !void {
	const main_buf_sequence = "\x1B[?1049l";
    try w.print("{s}", .{ main_buf_sequence });
    try w.flush();
}

fn getWinSize(f: *std.fs.File) !std.posix.winsize {
	var winsize: std.c.winsize = undefined;
	const fd = f.handle;
	const rc = std.c.ioctl(fd, std.c.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (@as(isize, rc) < 0) {
        return error.IoctIError; // handle error appropriately
    }

    return winsize;
}

fn printCentered(w: *std.io.Writer, buffer: []const u8, winsize: std.posix.winsize) !void {
	const center_row = winsize.row / 2;
	const center_col = if (winsize.col > buffer.len)
		(winsize.col - @as(u16, @intCast(buffer.len))) / 2
		else 0;

	try w.print("\x1B[{d};{d}H{s}", .{ center_row, center_col, buffer });
    try w.flush();
}
