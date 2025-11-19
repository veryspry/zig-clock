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
    defer displayMainBuffer(stdout) catch {};

    try hideCursor(stdout);
    defer showCursor(stdout) catch {};

    // const stdin_file = std.fs.File.stdin();
    // try disableRawMode(stdin_file.handle);

    var last_winsize: ?std.posix.winsize = null;

    while (!should_exit.load(.seq_cst)) {
    	const winsize = try getWinSize(&stdout_file);

   		var message_buffer: [1024]u8 = undefined;

   		const time = getCurrentTime();
     	const time_msg = try std.fmt.bufPrint(&message_buffer, "{d}:{d}:{d}", .{ time.hours, time.minutes, time.seconds });
       	try printCentered(stdout, time_msg, winsize);

     	if (last_winsize == null or last_winsize.?.row != winsize.row or last_winsize.?.col != winsize.col) {
      		try clearPrompt(stdout);

      		// var message_buffer: [1024]u8 = undefined;
            const size_msg = try std.fmt.bufPrint(&message_buffer, "Rows: {d}, Cols: {d}", .{ winsize.row, winsize.col });

            try printBottomLeft(stdout, size_msg, winsize);

            last_winsize = winsize;
      	}

       	std.Thread.sleep(10_000_000);
    }
}

var should_exit = std.atomic.Value(bool).init(false);

fn handleSigInt(_: c_int) callconv(.c) void {
	// signal that the main loop should exit
	// then, anything that is defered can run and clean up
	should_exit.store(true, .seq_cst);
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

fn disableRawMode(fd: std.posix.fd_t) !void {
	const original_termios = try std.posix.tcgetattr(fd);

	defer std.posix.tcsetattr(fd, .FLUSH, original_termios) catch {};

	var termios = original_termios;

	// TODO this does not work
	// termios.lflag &= ~@as(std.posix.system.tc_lflag_t, std.c.tc_lflag_t.ECHO | std.c.ICANON | std.c.ISIG);

	// TODO and this doesn't work either
	termios.lflag.ECHO = false; // don't show typed chars
	termios.lflag.ICANON = false; // disable line buffering
	termios.lflag.ISIG = false; // disable Ctrl+C, Ctrl+Z
	try std.posix.tcsetattr(fd, .FLUSH, termios);
}

fn clearPrompt(w: *std.io.Writer) !void {
	const clear_sequence = "\x1b[2J";
    try w.print("{s}", .{ clear_sequence });
    try w.flush();
}

fn hideCursor(w: *std.io.Writer) !void {
	const hide_cursor_sequence = "\x1B[?25l";
	try w.print("{s}", .{ hide_cursor_sequence });
	try w.flush();
}

fn showCursor(w: *std.io.Writer) !void {
	const show_cursor_sequence = "\x1B[?25h";
	try w.print("{s}", .{ show_cursor_sequence });
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

	try clearEntireLine(w, center_row);
	try w.print("\x1B[{d};{d}H{s}", .{ center_row, center_col, buffer });
    try w.flush();
}

fn printBottomLeft(w: *std.io.Writer, buffer: []const u8, winsize: std.posix.winsize) !void {
	const bottom_row = winsize.row;
	const left_col = 1;
	try clearEntireLine(w, winsize.row);
	try w.print("\x1B[{d};{d}H{s}", .{ bottom_row, left_col, buffer });
    try w.flush();
}

// Or clear the entire line regardless of cursor position:
fn clearEntireLine(w: *std.io.Writer, row: u16) !void {
    try w.print("\x1B[{d};1H\x1B[2K", .{ row });
    try w.flush();
}

const Time = struct {
	seconds: u6,
	minutes: u6,
	hours: u5,
};

fn getCurrentTime() Time {
	const timestamp = std.time.timestamp();
	const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
	const day_seconds = epoch_seconds.getDaySeconds();

	const seconds = day_seconds.getSecondsIntoMinute();
	const minutes = day_seconds.getMinutesIntoHour();
 	const hours = day_seconds.getHoursIntoDay();

	const time: Time = .{
		.seconds = seconds,
		.minutes = minutes,
		.hours = hours,
	};

	return time;
}
