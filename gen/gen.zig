const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("xml");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    if (args.len != 3) {
        std.debug.print("wrong number of arguments\n", .{});
        std.process.exit(1);
    }
    defer std.process.argsFree(alloc, args);

    const input_file_path = args[1];
    var input_file = std.fs.cwd().openFile(input_file_path, .{}) catch |err| {
        std.debug.print("cannot open file '{s}': {s}\n", .{ input_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer input_file.close();
    var buf_reader = std.io.bufferedReader(input_file.reader());
    var input_reader = buf_reader.reader();
    const max_xml_size = 1024 * 1024 * 1024;
    const input_contents = input_reader.readAllAlloc(alloc, max_xml_size) catch |err| {
        switch (err) {
            error.StreamTooLong => std.debug.print("xml longer than {d}\n", .{max_xml_size}),
            else => std.debug.print("cannot read file: {s}\n", .{@errorName(err)}),
        }
        std.process.exit(1);
    };
    defer alloc.free(input_contents);

    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("cannot create file '{s}': {s}\n", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer output_file.close();

    const parsed_file = try xml.parse(alloc, input_contents);
    defer parsed_file.deinit();

    var builder = ProtocolData.Builder.init(alloc);
    defer builder.deinit();
    try builder.parseProtocol(&parsed_file, alloc);
    const protocol_data = try builder.finish();
    try protocol_data.codegen(output_file.writer());
    defer protocol_data.deinit();
}

const CaseConverter = struct {
    str: []const u8,
    capitalize_first: bool,

    pub fn format(self: CaseConverter, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.str.len == 0) {
            return;
        }

        var words = std.mem.splitSequence(u8, self.str, "_");
        var first = true;

        while (words.next()) |word| {
            if (word.len == 0) {
                continue;
            }

            if ((first and self.capitalize_first) or !first) {
                try writer.writeByte(std.ascii.toUpper(word[0]));
                try writer.writeAll(word[1..]);
            } else {
                try writer.writeAll(word);
            }

            first = false;
        }
    }

    fn snake_to_pascal(str: []const u8) CaseConverter {
        return .{
            .str = str,
            .capitalize_first = true,
        };
    }

    fn snake_to_camel(str: []const u8) CaseConverter {
        return .{
            .str = str,
            .capitalize_first = false,
        };
    }
};

const ProtocolData = struct {
    interfaces: []Interface,
    alloc: Allocator,

    const Builder = struct {
        interfaces: std.ArrayList(Interface),
        alloc: Allocator,

        fn init(alloc: Allocator) Builder {
            return .{ .interfaces = std.ArrayList(Interface).init(alloc), .alloc = alloc };
        }

        fn finish(self: *Builder) !ProtocolData {
            return .{ .interfaces = try self.interfaces.toOwnedSlice(), .alloc = self.alloc };
        }

        fn parseProtocol(self: *Builder, document: *const xml.Document, alloc: Allocator) !void {
            if (!std.mem.eql(u8, document.root.tag, "protocol")) {
                return error.NoProtocol;
            }

            var elements = document.root.elements();
            while (elements.next()) |element| {
                if (std.mem.eql(u8, element.tag, "interface")) {
                    try self.interfaces.append(try Interface.parse(element, alloc));
                    continue;
                }

                if (!std.mem.eql(u8, element.tag, "copyright")) {
                    std.log.warn("Found unexpected child of the 'protocol' element with tag {s}", .{element.tag});
                }
            }
        }

        fn deinit(self: *const Builder) void {
            for (self.interfaces.items) |item| {
                item.deinit();
            }
            self.interfaces.deinit();
        }
    };

    fn codegen(self: *const ProtocolData, writer: anytype) !void {
        // write imports
        try writer.writeAll(
            \\const std = @import("std");
            \\const wayland_base = @import("wayland_base");
            \\
            \\
        );

        // write interface enum
        try writer.writeAll(
            \\pub const Interface = enum {
            \\
        );

        for (self.interfaces) |interface| {
            try std.fmt.format(writer,
                \\    {s},
                \\
            , .{interface.name});
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );

        // write event enum
        try writer.writeAll(
            \\pub const Event = union(Interface) {
            \\
        );

        for (self.interfaces) |interface| {
            try std.fmt.format(writer,
                \\    {s}: {s}.Event,
                \\
            , .{ interface.name, CaseConverter.snake_to_pascal(interface.name) });
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );

        // write request enum
        try writer.writeAll(
            \\pub const Request = union(Interface) {
            \\
        );

        for (self.interfaces) |interface| {
            try std.fmt.format(writer,
                \\    {s}: {s}.Request,
                \\
            , .{ interface.name, CaseConverter.snake_to_pascal(interface.name) });
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );

        for (self.interfaces) |interface| {
            try interface.codegen(writer);
        }
    }

    fn deinit(self: *const ProtocolData) void {
        for (self.interfaces) |interface| {
            interface.deinit();
        }
        self.alloc.free(self.interfaces);
    }
};

const Interface = struct {
    name: []const u8,
    version: u32,
    summary: []const u8,
    description: []const u8,
    events: []RequestEvent,
    requests: []RequestEvent,
    enums: []Enum,
    alloc: Allocator,

    fn parse(element: *const xml.Element, alloc: Allocator) !Interface {
        const name = element.getAttribute("name") orelse {
            return error.NoInterfaceName;
        };

        const version_str = element.getAttribute("version") orelse {
            return error.NoVersion;
        };

        const version = try std.fmt.parseInt(u32, version_str, 10);

        var events = std.ArrayList(RequestEvent).init(alloc);
        errdefer {
            for (events.items) |item| {
                item.deinit();
            }
            events.deinit();
        }
        var requests = std.ArrayList(RequestEvent).init(alloc);
        errdefer {
            for (requests.items) |item| {
                item.deinit();
            }
            requests.deinit();
        }
        var enums = std.ArrayList(Enum).init(alloc);
        errdefer {
            for (enums.items) |item| {
                item.deinit();
            }
            enums.deinit();
        }
        var summary: ?[]const u8 = null;
        var description: ?[]const u8 = null;

        var children = element.elements();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.tag, "description")) {
                getDescription(&summary, &description, child);
            }

            if (std.mem.eql(u8, child.tag, "event")) {
                try events.append(try RequestEvent.parse(child, alloc));
            }

            if (std.mem.eql(u8, child.tag, "request")) {
                try requests.append(try RequestEvent.parse(child, alloc));
            }

            if (std.mem.eql(u8, child.tag, "enum")) {
                try enums.append(try Enum.parse(child, alloc));
            }
        }

        return .{
            .name = name,
            .version = version,
            .summary = summary orelse return error.NoSummary,
            .description = description orelse return error.NoDescription,
            .events = try events.toOwnedSlice(),
            .requests = try requests.toOwnedSlice(),
            .enums = try enums.toOwnedSlice(),
            .alloc = alloc,
        };
    }

    fn deinit(self: *const Interface) void {
        for (self.events) |event| {
            event.deinit();
        }

        for (self.requests) |request| {
            request.deinit();
        }

        for (self.enums) |enum_| {
            enum_.deinit();
        }

        self.alloc.free(self.events);
        self.alloc.free(self.requests);
        self.alloc.free(self.enums);
    }

    fn codegen(self: *const Interface, writer: anytype) !void {
        try printDescription(self.summary, self.description, 0, writer);

        try std.fmt.format(writer,
            \\pub const {s} = struct {{
            \\    pub const version = {d};
            \\    id: u32,
            \\
            \\
        , .{ CaseConverter.snake_to_pascal(self.name), self.version });

        try std.fmt.format(writer,
            \\    pub const Request = struct {{
            \\
        , .{});

        for (self.requests, 0..) |request, i| {
            try request.codegenStruct(i, writer);
        }

        try std.fmt.format(writer,
            \\    }};
            \\
            \\
        , .{});

        try std.fmt.format(writer,
            \\    pub const Event = struct {{
            \\
        , .{});

        for (self.events, 0..) |event, i| {
            try event.codegenStruct(i, writer);
        }

        try std.fmt.format(writer,
            \\    }};
            \\
            \\
        , .{});

        for (self.events) |event| {
            try event.codegenFunction(self, false, writer);
        }

        for (self.requests) |request| {
            try request.codegenFunction(self, true, writer);
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );
    }
};

fn printDescription(summary: ?[]const u8, desc: ?[]const u8, comptime indent: usize, writer: anytype) !void {
    const indent_str = "    " ** indent;
    if (summary) |s| {
        try std.fmt.format(writer,
            \\{s}/// {s}
            \\
        , .{ indent_str, s });
    }

    if (desc) |d| {
        var desc_lines = std.mem.splitSequence(u8, d, "\n");
        while (desc_lines.next()) |line| {
            try std.fmt.format(writer,
                \\{s}/// {s}
                \\
            , .{ indent_str, std.mem.trim(u8, line, " \t") });
        }
    }
}

fn getDescription(summary: *?[]const u8, desc: *?[]const u8, element: *const xml.Element) void {
    if (element.children.len >= 1) {
        desc.* = switch (element.children[0]) {
            .char_data => |data| data,
            else => null,
        };
    }

    summary.* = element.getAttribute("summary");
}

const RequestEvent = struct {
    name: []const u8,
    summary: []const u8,
    description: ?[]const u8,
    args: []Arg,
    alloc: Allocator,

    fn parse(element: *const xml.Element, alloc: Allocator) !RequestEvent {
        const name_str = element.getAttribute("name") orelse return error.NoName;
        const name = if (std.mem.eql(u8, name_str, "error")) "err" else name_str;

        var summary: ?[]const u8 = null;
        var description: ?[]const u8 = null;
        var args = std.ArrayList(Arg).init(alloc);
        errdefer args.deinit();

        var children = element.elements();
        while (children.next()) |child| {
            if (std.mem.eql(u8, child.tag, "description")) {
                getDescription(&summary, &description, child);
            }

            if (std.mem.eql(u8, child.tag, "arg")) {
                try args.append(try Arg.parse(child));
            }
        }

        return .{
            .name = name,
            .summary = summary orelse return error.NoSummary,
            .description = description,
            .args = try args.toOwnedSlice(),
            .alloc = alloc,
        };
    }

    fn codegenStruct(self: *const RequestEvent, opcode: usize, writer: anytype) !void {
        try printDescription(self.summary, self.description, 2, writer);

        try std.fmt.format(writer,
            \\        pub const {s} = struct {{
            \\            pub const opcode = {d};
            \\
        , .{ CaseConverter.snake_to_pascal(self.name), opcode });

        for (self.args) |arg| {
            try arg.codegenAsStructField(writer);
        }

        try std.fmt.format(writer,
            \\        }};
            \\
            \\
        , .{});
    }

    fn codegenFunction(self: *const RequestEvent, parent: *const Interface, is_request: bool, writer: anytype) !void {
        var typed_new_ids: usize = 0;
        var untyped_new_ids: usize = 0;
        for (self.args) |arg| {
            switch (arg.ty) {
                .new_id_with_interface => typed_new_ids += 1,
                .new_id_without_interface => untyped_new_ids += 1,
                else => {},
            }
        }

        const contains_a_single_typed_output = typed_new_ids == 1 and untyped_new_ids == 0;
        const capitalized_prefix = if (is_request) "Request" else "Event";
        const lowercase_prefix = if (is_request) "request" else "event";

        try printDescription(self.summary, self.description, 2, writer);
        if (contains_a_single_typed_output) {
            var new_id_arg: Arg = undefined;
            for (self.args) |arg| {
                switch (arg.ty) {
                    .new_id_with_interface => {
                        new_id_arg = arg;
                        break;
                    },
                    else => {},
                }
            }

            try std.fmt.format(writer,
                \\    pub fn {s}{s}(
                \\        self: *const {s},
                \\        params: {s}.{s}.{s},
                \\        writer: anytype,
                \\        interface_registry: *std.AutoHashMap(u32, Interface),
                \\    ) !{s} {{
                \\        try wayland_base.sendMessage(writer, params, self.id);
                \\        try interface_registry.put(params.registry, Interface.{s});
                \\        return {s}{{ .id = params.{s} }};
                \\    }}
                \\
                \\
            , .{
                lowercase_prefix,
                CaseConverter.snake_to_pascal(self.name),
                CaseConverter.snake_to_pascal(parent.name),
                CaseConverter.snake_to_pascal(parent.name),
                capitalized_prefix,
                CaseConverter.snake_to_pascal(self.name),
                CaseConverter.snake_to_pascal(new_id_arg.ty.new_id_with_interface),
                new_id_arg.ty.new_id_with_interface,
                CaseConverter.snake_to_pascal(new_id_arg.ty.new_id_with_interface),
                new_id_arg.name,
            });
        } else {
            try std.fmt.format(writer,
                \\    pub fn {s}{s}(
                \\        self: *const {s},
                \\        params: {s}.{s}.{s},
                \\        writer: anytype,
                \\    ) !void {{
                \\        try wayland_base.sendMessage(writer, params, self.id);
                \\    }}
                \\
                \\
            , .{
                lowercase_prefix,
                CaseConverter.snake_to_pascal(self.name),
                CaseConverter.snake_to_pascal(parent.name),
                CaseConverter.snake_to_pascal(parent.name),
                capitalized_prefix,
                CaseConverter.snake_to_pascal(self.name),
            });
        }
    }

    fn deinit(self: *const RequestEvent) void {
        self.alloc.free(self.args);
    }
};

const Arg = struct {
    name: []const u8,
    ty: ArgType,
    summary: []const u8,

    fn parse(element: *const xml.Element) !Arg {
        const name = element.getAttribute("name") orelse return error.NoName;
        const summary = element.getAttribute("summary") orelse return error.NoSummary;

        const type_str = element.getAttribute("type") orelse return error.NoType;

        var ty: ArgType = undefined;
        if (std.mem.eql(u8, type_str, "int")) {
            ty = ArgType{ .int = undefined };
        } else if (std.mem.eql(u8, type_str, "uint")) {
            ty = ArgType{ .uint = undefined };
        } else if (std.mem.eql(u8, type_str, "fixed")) {
            ty = ArgType{ .fixed = undefined };
        } else if (std.mem.eql(u8, type_str, "string")) {
            ty = ArgType{ .string = undefined };
        } else if (std.mem.eql(u8, type_str, "object")) {
            ty = ArgType{ .object = undefined };
        } else if (std.mem.eql(u8, type_str, "array")) {
            ty = ArgType{ .array = undefined };
        } else if (std.mem.eql(u8, type_str, "fd")) {
            ty = ArgType{ .fd = undefined };
        } else if (std.mem.eql(u8, type_str, "new_id")) {
            if (element.getAttribute("interface")) |interface| {
                ty = ArgType{ .new_id_with_interface = interface };
            } else {
                ty = ArgType{ .new_id_without_interface = undefined };
            }
        }

        return .{
            .name = name,
            .ty = ty,
            .summary = summary,
        };
    }

    fn codegenAsStructField(self: *const Arg, writer: anytype) !void {
        try printDescription(self.summary, null, 3, writer);
        switch (self.ty) {
            .new_id_without_interface => {
                try std.fmt.format(writer,
                    \\            {s}: {s},
                    \\            {s}_interface_name: [:0]const u8,
                    \\            {s}_interface_version: u32,
                    \\
                , .{ self.name, self.ty.asZigTypeString(), self.name, self.name });
            },
            else => {
                try std.fmt.format(writer,
                    \\            {s}: {s},
                    \\
                , .{ self.name, self.ty.asZigTypeString() });
            },
        }
    }
};

const Enum = struct {
    entries: []const EnumEntry,
    description: ?[]const u8,
    summary: ?[]const u8,
    alloc: Allocator,

    fn parse(element: *const xml.Element, alloc: Allocator) !Enum {
        var entries = std.ArrayList(EnumEntry).init(alloc);
        errdefer entries.deinit();

        var summary: ?[]const u8 = null;
        var description: ?[]const u8 = null;

        var elements = element.elements();
        while (elements.next()) |child| {
            if (std.mem.eql(u8, child.tag, "description")) {
                getDescription(&summary, &description, child);
            }

            if (std.mem.eql(u8, child.tag, "entry")) {
                try entries.append(try EnumEntry.parse(child));
            }
        }

        return .{
            .summary = summary,
            .entries = try entries.toOwnedSlice(),
            .description = description,
            .alloc = alloc,
        };
    }

    fn deinit(self: *const Enum) void {
        self.alloc.free(self.entries);
    }
};

const EnumEntry = struct {
    name: []const u8,
    value: u32,
    summary: ?[]const u8,

    fn parse(element: *xml.Element) !EnumEntry {
        const name_str = element.getAttribute("name") orelse return error.NoName;
        const name = if (std.mem.eql(u8, name_str, "error"))
            "err"
        else
            name_str;

        const value_str = element.getAttribute("value") orelse return error.NoName;
        const value = if (value_str.len > 2 and value_str[1] == 'x')
            try std.fmt.parseInt(u32, value_str[2..], 16)
        else
            try std.fmt.parseInt(u32, value_str, 10);

        const summary = element.getAttribute("summary");

        return .{
            .name = name,
            .value = value,
            .summary = summary,
        };
    }
};

const ArgType = union(enum) {
    int,
    uint,
    fixed,
    string,
    object,
    new_id_with_interface: []const u8,
    new_id_without_interface,
    array,
    fd,

    fn asZigTypeString(self: *const ArgType) []const u8 {
        return switch (self.*) {
            .int => "i32",
            .uint => "u32",
            .fixed => "u32",
            .string => "[:0]const u8",
            .object => "u32",
            .new_id_with_interface => "u32",
            .new_id_without_interface => "u32",
            .array => "[]const u8",
            .fd => "void",
        };
    }
};
