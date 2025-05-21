const std = @import("std");

const assets_dir = "assets";

const buildGame = @import("engine").buildGame;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const engine_dep = b.dependency("engine", .{
        .target = target,
        .build_examples = false,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("engine", engine_dep.module("engine"));

    var game = buildGame(
        b,
        target,
        optimize,
        engine_dep,
        engine_dep.module("engine"),
        "game",
        exe_mod,
        &.{},
    );

    game.dependOn(engine_dep.builder.getInstallStep());
    b.default_step.dependOn(game);
}
