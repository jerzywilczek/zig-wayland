const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub fn headerFromMessage(message: anytype, object_id: u32) MessageHeader {
    var len = @as(u16, @sizeOf(MessageHeader));
    inline for (std.meta.fields(@TypeOf(message))) |field| {
        switch (field.type) {
            u32 => len += 4,
            i32 => len += 4,
            [:0]const u8 => len += 4 + roundUp(@field(message, field.name) + 1, 4),
            []const u8 => len += 4 + roundUp(@field(message, field.name), 4),
            void => {},
            else => @compileError("Cannot create a MessageHeader from " ++ @typeName(@TypeOf(message)) ++ ", field \"" ++ field.name ++ "\" has a wrong type."),
        }
    }

    return MessageHeader{
        .object_id = object_id,
        .opcode = @TypeOf(message).opcode,
        .size = len,
    };
}

fn roundUp(val: anytype, divisor: @TypeOf(val)) @TypeOf(val) {
    return (val + divisor - 1) / divisor * divisor;
}

pub const MessageHeader = if (builtin.cpu.arch.endian() == std.builtin.Endian.little)
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

pub fn sendMessage(writer: anytype, message: anytype, object_id: u32) !void {
    const endianness = builtin.cpu.arch.endian();
    const header = headerFromMessage(message, object_id);
    try writer.writeStruct(header);
    inline for (std.meta.fields(@TypeOf(message))) |field| {
        switch (field.type) {
            u32 => try writer.writeInt(u32, @field(message, field.name), endianness),
            i32 => try writer.writeInt(i32, @field(message, field.name), endianness),
            [:0]const u8 => {
                try writer.writeInt(u32, @intCast(@field(message, field.name).len));
                try writer.writeAll(@field(message, field.name));
                try writer.writeByte(0);
                const padding = (roundUp(@field(message, field.name) + 1, 4)) - (@field(message, field.name) + 1);
                for (0..padding) |_| {
                    try writer.writeByte(0);
                }
            },
            []const u8 => {
                try writer.writeInt(u32, @intCast(@field(message, field.name).len));
                try writer.writeAll(@field(message, field.name));
                const padding = (roundUp(@field(message, field.name), 4)) - (@field(message, field.name));
                for (0..padding) |_| {
                    try writer.writeByte(0);
                }
            },
            void => {},
            else => @compileError("Cannot send a message with struct " ++ @typeName(@TypeOf(message)) ++ ", field \"" ++ field.name ++ "\" has a wrong type."),
        }
    }
}
