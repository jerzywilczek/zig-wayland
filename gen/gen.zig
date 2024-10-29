const std = @import("std");

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 3) {
        std.debug.print("wrong number of arguments");
        std.process.exit(1);
    }

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        std.debug.print("cannot open file '{s}': {s}", .{ input_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer input_file.close();
    const input_reader = std.io.bufferedReader(input_file.reader());

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("cannot create file '{s}': {s}", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
}
