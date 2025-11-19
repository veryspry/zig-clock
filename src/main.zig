const std = @import("std");
const assert = std.debug.assert;
const zig_clock = @import("zig_clock");

pub fn main() !void {
	var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    while (true) {
    	try displayAltBuffer(stdout);
    	std.Thread.sleep(1000000000);
     	try displayMainBuffer(stdout);
     	std.Thread.sleep(1000000000);
    }
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
