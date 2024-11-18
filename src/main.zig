const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");

fn headerFromMessage(message: anytype, object_id: u32) MessageHeader {
    var len = @as(u16, @sizeOf(MessageHeader));
    inline for (std.meta.fields(@TypeOf(message))) |field| {
        switch (field.type) {
            u32 => len += 4,
            i32 => len += 4,
            else => @compileError("Cannot create a MessageHeader from " ++ @typeName(@TypeOf(message)) ++ ", field \"" ++ field.name ++ "\" has a wrong type."),
        }
    }

    return MessageHeader{
        .object_id = object_id,
        .opcode = @TypeOf(message).opcode,
        .size = len,
    };
}

const MessageHeader = if (builtin.cpu.arch.endian() == std.builtin.Endian.little)
    packed struct {
        object_id: u32,
        opcode: u16,
        size: u16,
    }
else
    packed struct {
        object_id: u32,
        size: u16,
        opcode: u16,
    };

const Interface = enum {
    wl_display,
    wl_callback,
    wl_registry,
};

const InterfaceRegistry = struct {
    const InterfaceMap = std.AutoHashMap(u32, Interface);
    map: InterfaceMap,

    fn init(alloc: Allocator) InterfaceRegistry {
        return InterfaceRegistry{
            .map = InterfaceMap.init(alloc),
        };
    }

    fn deinit(self: *InterfaceRegistry) void {
        self.map.deinit();
    }

    fn put(self: *InterfaceRegistry, id: u32, interface: Interface) !void {
        try self.map.put(id, interface);
    }
};

const WlDisplay = struct {
    const version = 1;
    id: u32,

    const SyncParams = struct {
        const opcode = 0;
        callback: u32,
    };

    const GetRegistryParams = struct {
        const opcode = 1;
        registry: u32,
    };

    fn getRegistry(self: *const WlDisplay, params: GetRegistryParams, writer: anytype, registry: *InterfaceRegistry) !WlRegistry {
        try sendMessage(writer, params, self.id);
        try registry.put(params.registry, Interface.wl_registry);
        return WlRegistry{ .id = params.registry };
    }
};

const WlRegistry = struct {
    const version = 1;
    id: u32,
};

fn sendMessage(writer: anytype, message: anytype, object_id: u32) !void {
    const endianness = builtin.cpu.arch.endian();
    const header = headerFromMessage(message, object_id);
    try writer.writeStruct(header);
    inline for (std.meta.fields(@TypeOf(message))) |field| {
        switch (field.type) {
            u32 => try writer.writeInt(u32, @field(message, field.name), endianness),
            i32 => try writer.writeInt(i32, @field(message, field.name), endianness),
            else => @compileError("Cannot send a message with struct " ++ @typeName(@TypeOf(message)) ++ ", field \"" ++ field.name ++ "\" has a wrong type."),
        }
    }
}

fn readResponse() !void {}

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
    const socket_reader = socket.reader()
    const wl_display = WlDisplay{ .id = 1 };
    var interface_registry = InterfaceRegistry.init(alloc);
    defer interface_registry.deinit();
    try interface_registry.put(1, Interface.wl_display);

    const wl_registry = try wl_display.getRegistry(.{ .registry = 2 }, socket_writer, &interface_registry);
    _ = wl_registry;
}
