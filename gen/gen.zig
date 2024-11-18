const std = @import("std");
const xml = @import("xml");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 3) {
        std.debug.print("wrong number of arguments\n", .{});
        std.process.exit(1);
    }
    defer std.process.argsFree(allocator, args);

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        std.debug.print("cannot open file '{s}': {s}\n", .{ input_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer input_file.close();
    var buf_reader = std.io.bufferedReader(input_file.reader());
    var input_reader = buf_reader.reader();
    const max_xml_size = 1024 * 1024 * 1024;
    const input_contents = input_reader.readAllAlloc(allocator, max_xml_size) catch |err| {
        switch (err) {
            error.StreamTooLong => std.debug.print("xml longer than {d}\n", .{max_xml_size}),
            else => std.debug.print("cannot read file: {s}\n", .{@errorName(err)}),
        }
        std.process.exit(1);
    };
    defer allocator.free(input_contents);

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("cannot create file '{s}': {s}\n", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer output_file.close();

    const parsed_file = try xml.parse(allocator, input_contents);
    defer parsed_file.deinit();

    try typegenDocument(&parsed_file, output_file.writer());
}

fn typegenDocument(document: *const xml.Document, writer: std.fs.File.Writer) !void {
    if (std.mem.eql(u8, document.root.tag, "protocol")) {
        for (document.root.children) |child| {
            switch (child) {
                .comment => {},
                .char_data => |data| if (!std.mem.eql(u8, std.mem.trim(u8, data, " \t\n\r"), "")) {
                    std.log.warn("Found unexpected char data in the 'protocol' element ({s}).\n", .{data});
                },
                .element => |element| if (std.mem.eql(u8, element.tag, "interface")) {
                    try typegenInterface(element, writer);
                } else if (std.mem.eql(u8, element.tag, "copyright")) {} else {
                    std.log.warn("Found unexpected child of the 'protocol' element with tag {s}", .{element.tag});
                },
            }
        }
    } else {
        return error.NoProtocol;
    }
}

fn typegenInterface(interface: *xml.Element, writer: std.fs.File.Writer) !void {
    std.debug.print("interface: {s}\n", .{interface.getAttribute("name").?});
    _ = writer;
}

const PrintParams = struct {
    indent: usize = 0,
};

fn printElement(element: *xml.Element, params: PrintParams, alloc: std.mem.Allocator) !void {
    var indent_builder = std.ArrayList(u8).init(alloc);
    try indent_builder.appendNTimes(' ', params.indent);
    const indent = try indent_builder.toOwnedSlice();
    defer alloc.free(indent);

    std.debug.print("{s}<{s}", .{ indent, element.tag });
    for (element.attributes) |attr| {
        std.debug.print(" {s}=\"{s}\"", .{ attr.name, attr.value });
    }
    std.debug.print(">\n", .{});

    for (element.children) |child| {
        switch (child) {
            .element => |el| try printElement(el, .{ .indent = params.indent + 2 }, alloc),
            .comment => {},
            .char_data => |data| try printChars(data, .{ .indent = params.indent + 2 }, alloc),
        }
    }

    std.debug.print("{s}</{s}>\n", .{ indent, element.tag });
}

fn printChars(str: []const u8, params: PrintParams, alloc: std.mem.Allocator) !void {
    var indent_builder = std.ArrayList(u8).init(alloc);
    try indent_builder.appendNTimes(' ', params.indent);
    const indent = try indent_builder.toOwnedSlice();
    defer alloc.free(indent);

    var iter = std.mem.splitSequence(u8, str, "\n");
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\n\r");
        if (trimmed.len > 0) {
            std.debug.print("{s}{s}\n", .{ indent, trimmed });
        }
    }
}
