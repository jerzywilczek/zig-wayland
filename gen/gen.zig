const std = @import("std");
const xml = @import("xml");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 3) {
        std.debug.print("wrong number of arguments", .{});
        std.process.exit(1);
    }

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        std.debug.print("cannot open file '{s}': {s}", .{ input_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer input_file.close();
    var buf_reader = std.io.bufferedReader(input_file.reader());
    var input_reader = buf_reader.reader();
    const max_xml_size = 1024 * 1024 * 1024;
    const input_contents = input_reader.readAllAlloc(arena, max_xml_size) catch |err| {
        switch (err) {
            error.StreamTooLong => std.debug.print("xml longer than {d}", .{max_xml_size}),
            else => std.debug.print("cannot read file: {s}", .{@errorName(err)}),
        }
        std.process.exit(1);
    };

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("cannot create file '{s}': {s}", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer output_file.close();

    const parsed_file = try xml.parse(arena, input_contents);
    _ = parsed_file;

    try output_file.writeAll(
        \\pub const test_message: []const u8 = "test";
    );
}
