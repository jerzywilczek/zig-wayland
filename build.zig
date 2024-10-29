const std = @import("std");

pub fn build(b: *std.Build) void {
    const gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = b.path("gen/gen.zig"),
        .target = b.graph.host,
    });

    const gen_step = b.addRunArtifact(gen);
    gen_step.addFileArg("assets/wayland.xml");
    const wayland_zig = gen_step.addOutputFileArg("wayland.zig");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "wayland_client",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("wayland", .{ .root_source_file = wayland_zig });

    b.installArtifact(exe);
}
