const std = @import("std");

pub fn build(b: *std.Build) void {
    const wayland_headers = b.path("assets/wayland.xml");

    const xml = b.addModule("xml", .{
        .root_source_file = b.path("vulkan-zig/src/xml.zig"),
    });

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = b.path("gen/gen.zig"),
        .target = b.graph.host,
    });

    gen.root_module.addImport("xml", xml);
    const gen_step = b.addRunArtifact(gen);
    gen_step.addFileArg(wayland_headers);
    const wayland_zig = gen_step.addOutputFileArg("wayland.zig");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "wayland_client",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const base_module = b.addModule("wayland_base", .{ .root_source_file = b.path("gen/wayland_base.zig") });
    const wayland_zig_module = b.addModule("wayland", .{ .root_source_file = wayland_zig });
    wayland_zig_module.addImport("wayland_base", base_module);

    exe.root_module.addImport("wayland", wayland_zig_module);

    b.installArtifact(exe);
}
