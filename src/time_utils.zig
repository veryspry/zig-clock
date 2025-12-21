const std = @import("std");

pub const Time = struct {
    seconds: u6,
    minutes: u6,
    hours: u5,
};

pub fn getCurrentTime() Time {
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
