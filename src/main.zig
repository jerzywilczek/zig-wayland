const std = @import("std");
const wayland = @import("wayland");

pub fn main() !void {
    std.debug.print("test message: {s}", .{wayland.test_message});
}
