
const ASCII_ART = struct {
	const Self = @This();

	symbols: [10][] const u8,

	fn index(ch: u8) usize {
		return switch(ch) {
			'0'...'9' => ch - 48,
			else => @panic("Unsuppoted character")
		};
	}

	pub fn get(self: *const Self, ch: u8) []const u8 {
		return self.symbols[Self.index(ch)];
	}
};


pub const ogre: ASCII_ART = .{
	.symbols = .{
		\\ ___
		\\/ _ \
		\\| | |
		\\| |_|
		\\\___/
		,
		\\ _
		\\/ |
		\\| |
		\\| |
		\\|_|
		,
		\\ ____
		\\|___ \
		\\__) |
		\\/ __/
		\\|_____|
		,
		\\ _____
		\\|___ /
		\\|_ \
		\\___) |
		\\|____/
		,
		\\ _  _
		\\| || |
		\\| || |_
		\\|__   _|
		\\  |_|
		,
		\\ ____
		\\| ___|
		\\|___ \
		\\ ___) |
		\\|____/
		,
		\\ __
		\\/ /_
		\\| '_ \
		\\| (_) |
		\\\___/
		,
		\\ _____
		\\|___  |
		\\  / /
		\\ / /
		\\/_/
		,
		\\ ___
		\\( _ )
		\\/ _ \
		\\| (_) |
		\\\___/
		,
		\\ ___
		\\/ _ \
		\\| (_) |
		\\\__, |
		\\ /_/
		,
	},
};
