const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const time_utils = @import("time_utils.zig");
const ascii_art = @import("ascii_art.zig");

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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var last_winsize: ?std.posix.winsize = null;

    var time_msg_buf: [8][]const u8 = undefined; // TODO can this be reused on every loop iteration?
    while (!should_exit.load(.seq_cst)) {
        const winsize = try getWinSize(&stdout_file);

        var message_buffer: [1024]u8 = undefined;

        const time_msg = try multiLineCharsToLines(
            allocator,
            ascii_art.ogre.getFromTime(
                time_utils.getCurrentTime(),
                &time_msg_buf,
            ),
        );
        defer allocator.free(time_msg);
        // try printCentered(stdout, time_msg, winsize);

        try printMultiLineTimeCentered(
            stdout,
            time_msg,
            winsize,
        );

        // const time = time_utils.getCurrentTime();
        // const time_msg = try std.fmt.bufPrint(&message_buffer, "{d}:{d}:{d}", .{ time.hours, time.minutes, time.seconds });
        // try printCentered(stdout, time_msg, winsize);

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
    try w.print("{s}", .{clear_sequence});
    try w.flush();
}

fn hideCursor(w: *std.io.Writer) !void {
    const hide_cursor_sequence = "\x1B[?25l";
    try w.print("{s}", .{hide_cursor_sequence});
    try w.flush();
}

fn showCursor(w: *std.io.Writer) !void {
    const show_cursor_sequence = "\x1B[?25h";
    try w.print("{s}", .{show_cursor_sequence});
    try w.flush();
}

fn displayAltBuffer(w: *std.io.Writer) !void {
    const alt_buf_sequence = "\x1B[?1049h";
    try w.print("{s}", .{alt_buf_sequence});
    try w.flush();
}

fn displayMainBuffer(w: *std.io.Writer) !void {
    const main_buf_sequence = "\x1B[?1049l";
    try w.print("{s}", .{main_buf_sequence});
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

fn printMultiLineTimeCentered(w: *std.io.Writer, lines: []const []const u8, winsize: std.posix.winsize) !void {
    const center_row = winsize.row / 2;
    const center_col = if (winsize.col > lines.len)
        (winsize.col - @as(u16, @intCast(lines.len))) / 2
    else
        0;

    var curr_row = @as(u16, @intCast((center_row / 2) - (lines.len / 2)));

    for (lines) |line| {
        try clearEntireLine(w, curr_row);
        try w.print("\x1B[{d};{d}H{s}", .{ curr_row, center_col, line });
        try w.flush();
        curr_row += 1;
    }
}

fn printCentered(w: *std.io.Writer, buffer: []const u8, winsize: std.posix.winsize) !void {
    const center_row = winsize.row / 2;
    const center_col = if (winsize.col > buffer.len)
        (winsize.col - @as(u16, @intCast(buffer.len))) / 2
    else
        0;

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
    try w.print("\x1B[{d};1H\x1B[2K", .{row});
    try w.flush();
}

const Dimensions = struct {
    width: u16,
    height: u16,
};

// get the dimensions of one multiline ASCII number for example
fn getBufDimensions(buffer: []const u8) Dimensions {
    var dimensions: Dimensions = .{
        .height = 0,
        .width = 0,
    };

    var lines = std.mem.splitScalar(u8, buffer, '\n');
    while (lines.next()) |line| {
        if (line.len > dimensions.width) {
            dimensions.width = std.math.cast(u16, line.len) orelse dimensions.width;
        }

        dimensions.height = dimensions.height + 1;
    }

    return dimensions;
}

test "getBufDimensions" {
    const buf1 =
        \\ ___
        \\/ _ \
        \\| | |
        \\| |_|
        \\\___/
    ;

    const dimensions1 = getBufDimensions(buf1);

    try std.testing.expectEqual(dimensions1.width, 5);
    try std.testing.expectEqual(dimensions1.height, 5);

    const buf2: []const u8 = "hey there test.";

    const dimensions2 = getBufDimensions(buf2);

    try std.testing.expectEqual(dimensions2.width, 15);
    try std.testing.expectEqual(dimensions2.height, 1);
}

const MultiLineChar = struct {
    height: u16,
    width: u16,
    lines: [][]const u8,

    pub fn deinit(self: *MultiLineChar, allocator: std.mem.Allocator) void {
        allocator.free(self.lines);
    }
};

fn createMultiLineChar(allocator: std.mem.Allocator, buffer: []const u8) !MultiLineChar {
    const dimensions = getBufDimensions(buffer);

    var lines = try allocator.alloc([]const u8, dimensions.height);

    var pieces = std.mem.splitScalar(u8, buffer, '\n');
    var i: usize = 0;
    while (pieces.next()) |line| {
        lines[i] = line;
        i += 1;
    }

    return MultiLineChar{ .height = dimensions.height, .width = dimensions.width, .lines = lines };
}

test "createMultiLineChar" {
    const buf1 =
        \\ ___
        \\/ _ \
        \\| | |
        \\| |_|
        \\\___/
    ;

    var char1 = try createMultiLineChar(testing.allocator, buf1);
    defer char1.deinit(testing.allocator);

    try std.testing.expectEqual(5, char1.width);
    try std.testing.expectEqual(5, char1.height);
    try std.testing.expectEqual(5, char1.lines.len);
    try std.testing.expectEqualStrings(char1.lines[0], " ___");
    try std.testing.expectEqualStrings(char1.lines[1], "/ _ \\");
    try std.testing.expectEqualStrings(char1.lines[2], "| | |");
    try std.testing.expectEqualStrings(char1.lines[3], "| |_|");
    try std.testing.expectEqualStrings(char1.lines[4], "\\___/");
}

fn multiLineCharsToLines(allocator: std.mem.Allocator, bufs: [][]const u8) ![]const []const u8 {
    const sep = ' ';

    var multi_line_chars = try allocator.alloc(MultiLineChar, bufs.len);
    defer allocator.free(multi_line_chars);
    defer {
        for (multi_line_chars) |*mlc| {
            mlc.deinit(allocator);
        }
    }

    var max_height: u16 = 0;
    for (bufs, 0..) |buf, i| {
        multi_line_chars[i] = try createMultiLineChar(allocator, buf);
        max_height = @max(max_height, multi_line_chars[i].height);
    }

    var lines = try allocator.alloc(std.ArrayList(u8), max_height);
    defer {
        for (lines) |*l| l.deinit(allocator);
        allocator.free(lines);
    }

    for (lines) |*l| {
        l.* = std.ArrayList(u8).empty;
    }

    for (multi_line_chars, 0..) |mlc, i| {
        // ensure that shorter things get aligned at the bottom of the final output slice
        const start = max_height - mlc.height;

        var pad_idx: usize = 0;
        while (pad_idx < max_height - mlc.height) {
            const old_len = lines[pad_idx].items.len;
            const pad_len = old_len + mlc.width;
            try lines[pad_idx].resize(allocator, pad_len + 1); // plus one for sep
            @memset(lines[pad_idx].items[old_len..pad_len], ' ');
            @memset(lines[pad_idx].items[pad_len..], sep);
            pad_idx += 1;
        }

        for (mlc.lines, 0..) |line, j| {
            const line_idx = j + start;

            if (i != 0) {
                // space between characters but skip adding it at the beginning
                try lines[line_idx].append(allocator, sep);
            }

            try lines[line_idx].appendSlice(allocator, line);

            const pad_len = mlc.width - line.len;
            if (pad_len > 0 and i + 1 < multi_line_chars.len) {
                // pad lines to keep spacing consistent unless on the last item
                const old_len = lines[line_idx].items.len;
                try lines[line_idx].resize(allocator, old_len + pad_len);
                @memset(lines[line_idx].items[old_len..], ' ');
            }
        }
    }

    var result = try allocator.alloc([]const u8, max_height);
    for (lines, 0..) |*line, curr| {
        result[curr] = try line.toOwnedSlice(allocator);
    }
    return result;
    // return lines;
}

fn combineMultiLineCharLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]u8 {
    var total_len = lines.len - 1; // initialize size with the number of newlines needed

    for (lines) |line| {
        total_len += line.len;
    }

    var result = try allocator.alloc(u8, total_len);

    var index: usize = 0;
    for (lines, 0..) |line, j| {
        std.mem.copyForwards(u8, result[index..], line);
        index += line.len;

        if (j + 1 < lines.len) {
            result[index] = '\n';
            index += 1;
        }
    }

    return result;
}

test "combineMultiLineCharLines()" {
    const buf1 =
        \\ ___
        \\/ _ \
        \\| | |
        \\| |_|
        \\\___/
    ;
    const buf2 =
        \\ _
        \\/ |
        \\| |
        \\| |
        \\|_|
    ;
    const buf3 =
        \\ _ 
        \\(_)
        \\ _ 
        \\(_)
    ;

    const expectedRes1 =
        \\ ___   _
        \\/ _ \ / |
        \\| | | | |
        \\| |_| | |
        \\\___/ |_|
    ;

    const result1 = try combineMultiLineCharLines(
        testing.allocator,
        &[_][]const u8{ buf1, buf2 },
    );

    defer testing.allocator.free(result1);
    try testing.expectEqualStrings(expectedRes1, result1);

    const expectedRes2 =
        \\ ___       _
        \\/ _ \  _  / |
        \\| | | (_) | |
        \\| |_|  _  | |
        \\\___/ (_) |_|
    ;

    const result2 = try combineMultiLineCharLines(testing.allocator, &[_][]const u8{ buf1, buf3, buf2 });
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings(expectedRes2, result2);
}
