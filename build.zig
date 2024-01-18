const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const static = b.option(
        bool,
        "static",
        "statically link C dependencies",
    ) orelse false;

    const zenolith_dep = b.dependency("zenolith", .{ .target = target, .optimize = optimize });
    const zenolith_sdl2_dep = b.dependency("zenolith_sdl2", .{
        .target = target,
        .optimize = optimize,
        .static = static,
    });

    const assets_mod = b.createModule(.{ .root_source_file = .{ .path = "assets.zig" } });

    inline for (.{ "themeswitcher", "counter" }) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = .{ .path = "src/" ++ name ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("assets", assets_mod);
        exe.root_module.addImport("zenolith", zenolith_dep.module("zenolith"));
        exe.root_module.addImport("zenolith-sdl2", zenolith_sdl2_dep.module("zenolith-sdl2"));

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step("run-" ++ name, "Run the " ++ name ++ " example");
        run_step.dependOn(&run_cmd.step);
    }
}
