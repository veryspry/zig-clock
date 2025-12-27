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
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prev_frame: ?Frame = null;
    var prev_winsize: ?std.posix.winsize = null;

    var time_chars_buf: [8][]const u8 = undefined;
    while (!should_exit.load(.seq_cst)) {
        const winsize = try getWinSize(&stdout_file);

        if (prev_winsize == null or prev_winsize.?.row != winsize.row or prev_winsize.?.col != winsize.col) {
            // if winsize changes, than rerender from scratch
            try clearPrompt(stdout);
            prev_winsize = winsize;
            prev_frame = null;
        }

        const frame = try initFrame(allocator, winsize);

        for (frame.lines, 0..) |_, i| {
            if (i == 0 or i == frame.row - 1) {
                _ = try std.fmt.bufPrint(frame.lines[i], "Rows: {d}, Cols: {d}", .{ winsize.row, winsize.col });
            }
        }

        const ascii_chars = ascii_art.ogre.getFromTime(
            time_utils.getCurrentTime(),
            &time_chars_buf,
        );

        const start_line = 4;
        var curr_pos: usize = 0;

        for (ascii_chars) |char| {
            var mlc = try createMultiLineChar(allocator, char);
            defer mlc.deinit(allocator);
            for (mlc.lines, 0..) |line, i| {
                _ = try std.fmt.bufPrint(frame.lines[start_line + i][curr_pos..], "{s}", .{line});
            }

            curr_pos += mlc.width + 1;
        }

        try drawFrame(stdout, frame, prev_frame);

        if (prev_frame) |f| {
            f.deinit(allocator);
        }

        prev_frame = frame;

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

const Frame = struct {
    const Self = @This();

    row: u16,
    col: u16,
    lines: [][]u8,

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        for (self.lines) |line| {
            allocator.free(line);
        }
        allocator.free(self.lines);
    }
};

fn initFrame(allocator: std.mem.Allocator, winsize: std.posix.winsize) !Frame {
    const lines = try allocator.alloc([]u8, winsize.row);

    for (lines) |*line| {
        line.* = try allocator.alloc(u8, winsize.col);
        @memset(line.*, ' ');
    }

    const frame: Frame = .{
        .row = winsize.row,
        .col = winsize.col,
        .lines = lines,
    };

    return frame;
}

fn drawFrame(w: *std.io.Writer, curr_frame: Frame, prev_frame: ?Frame) !void {
    // todo take prev_frame and do diffing
    for (curr_frame.lines, 0..) |line, i| {
        var changed = true;

        if (prev_frame) |pf| {
            changed = !std.mem.eql(u8, pf.lines[i], line);
        }

        if (changed) {
            try moveCursor(w, i + 1, 1);
            try clearLine(w);
            try w.writeAll(line);
            try w.flush();
            // reposition cursor to reset the auto wrap flag
            try moveCursor(w, 1, 1);
        }
    }
}

fn clearLine(writer: anytype) !void {
    try writer.writeAll("\x1b[2K");
}

fn clearPrompt(w: *std.io.Writer) !void {
    // const clear_sequence = "\x1b[2J";
    // try w.print("{s}", .{clear_sequence});
    // clear screen and put cursor at 1,1
    try w.writeAll("\x1b[2J\x1b[H");
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

// Moves the cursor position. Note that row and col are 1 index NOT 0 indexed
fn moveCursor(writer: anytype, row: usize, col: usize) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
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
        for (self.lines) |line| {
            allocator.free(line);
        }
        allocator.free(self.lines);
    }
};

fn createMultiLineChar(allocator: std.mem.Allocator, buffer: []const u8) !MultiLineChar {
    const dimensions = getBufDimensions(buffer);

    var lines = try allocator.alloc([]const u8, dimensions.height);

    var pieces = std.mem.splitScalar(u8, buffer, '\n');

    var max_width: usize = 0;
    while (pieces.next()) |line| {
        max_width = @max(max_width, line.len);
    }

    pieces.reset();

    var i: usize = 0;
    while (pieces.next()) |piece| {
        const piece_len = piece.len;
        const pad_len = @max(0, max_width - piece_len);
        const line = try allocator.alloc(u8, piece_len + pad_len);
        @memcpy(line[0..piece_len], piece);
        @memset(line[piece_len..], ' ');

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

fn multiLineCharsToLines(allocator: std.mem.Allocator, bufs: []const []const u8) ![]const []const u8 {
    const sep = ' ';

    var multi_line_chars = try allocator.alloc(MultiLineChar, bufs.len);
    defer {
        for (multi_line_chars) |*mlc| {
            mlc.deinit(allocator);
        }
        allocator.free(multi_line_chars);
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
}

test "multiLineCharsToLines()" {
    const zero =
        \\ ___
        \\/ _ \
        \\| | |
        \\| |_|
        \\\___/
    ;

    const one =
        \\ _
        \\/ |
        \\| |
        \\| |
        \\|_|
    ;

    const colon =
        \\ _
        \\(_)
        \\ _
        \\(_)
    ;

    const expectedRes1: []const []const u8 = &[_][]const u8{
        " ___       _",
        "/ _ \\  _  / |",
        "| | | (_) | |",
        "| |_|  _  | |",
        "\\___/ (_) |_|",
    };

    const res1 = try multiLineCharsToLines(
        testing.allocator,
        &[_][]const u8{ zero, colon, one },
    );

    defer {
        for (res1) |line| {
            testing.allocator.free(line);
        }
        testing.allocator.free(res1);
    }

    try testing.expect(expectedRes1.len == res1.len);
    for (expectedRes1, 0..) |line, i| {
        try testing.expectEqualStrings(line, res1[i]);
    }
}
