const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const xdg_runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
    const wayland_display = std.posix.getenv("WAYLAND_DISPLAY") orelse return error.NoWaylandDisplay;
    const wayland_socket_path = try std.fs.path.joinZ(alloc, &.{ xdg_runtime_dir, wayland_display });
    defer alloc.free(wayland_socket_path);
    const socket = try std.net.connectUnixSocket(wayland_socket_path);

    const socket_writer = socket.writer();
    const wl_display = wayland.WlDisplay{ .id = 1 };
    var interface_registry = std.AutoHashMap(u32, wayland.Interface).init(alloc);
    defer interface_registry.deinit();
    try interface_registry.put(1, wayland.Interface.wl_display);

    const wl_registry = try wl_display.requestGetRegistry(.{ .registry = 2 }, socket_writer, &interface_registry);
    _ = wl_registry;
}
