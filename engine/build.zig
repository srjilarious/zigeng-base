const std = @import("std");
const builtin = std.builtin;

const assets_dir = "assets";

fn addArchIncludes(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep: *std.Build.Step.Compile) !void {
    _ = optimize;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot == null) {
                @panic("Pass '--sysroot \"~/.cache/emscripten/sysroot\"'");
            }

            const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "include" }) catch @panic("Out of memory");
            defer b.allocator.free(cache_include);

            var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch {
                @panic("No emscripten cache. Generate it!");
            };

            dir.close();
            dep.addIncludePath(.{ .cwd_relative = cache_include });
        },
        else => {},
    }
}

pub const EngineData = struct {
    engine_lib: *std.Build.Step.Compile,
    engine_mod: *std.Build.Module,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_examples = b.option(bool, "build_examples", "Build the examples") orelse true;

    // Define the engine build steps, returning a ref to the step and the engine module.
    const engDat = buildEngine(b, target, optimize);

    // Define examples
    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        assets: []const []const u8,
    }{
        .{ .name = "quick", .path = "examples/quick.zig", .assets = &.{} },
    };

    // Create a "build-all" option that builds everything
    const build_all_step = b.step("build-all", "Build all examples");

    if (build_examples) {
        // Build each example
        for (examples) |example_info| {
            const exe_mod = b.createModule(.{
                .root_source_file = b.path(example_info.path),
                .target = target,
                .optimize = optimize,
            });
            const ex_step = buildExample(
                b,
                target,
                optimize,
                engDat.engine_lib,
                engDat.engine_mod,
                example_info.name,
                exe_mod,
                example_info.assets,
            );
            // const install_exe = b.addInstallArtifact(exe, .{
            //     .dest_dir = .{
            //         .override = .{ .custom = b.pathJoin(&.{ "bin", example_info.name }) },
            //     },
            // });

            build_all_step.dependOn(ex_step);
        }
    }

    // Make build-all the default step
    b.default_step.dependOn(build_all_step);
}

fn buildEngine(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) EngineData {
    // Create the engine module
    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the engine library
    const engine_lib = blk: {
        if (target.result.os.tag != .emscripten) {
            const lib = b.addStaticLibrary(.{
                .name = "engine",
                .root_module = engine_mod,
            });
            b.installArtifact(lib);
            break :blk lib;
        } else {
            const obj = b.addObject(.{
                .name = "engine_obj",
                .root_module = engine_mod,
            });

            // For emscripten builds, we need to use an object file, so we install it to a predetermined place
            // and have examples/games compile against that.
            const installObjStep = b.addInstallFile(obj.getEmittedBin(), "web/engine.o");
            b.getInstallStep().dependOn(&installObjStep.step);

            break :blk obj;
        }
    };

    // GLFW
    const zglfw = b.dependency("zglfw", .{ .target = target });
    const zglfw_mod = zglfw.module("root");
    engine_mod.addImport("zglfw", zglfw_mod);
    // Emscripten brings in its own version of GLFW, so only link in a native build.
    if (target.result.os.tag != .emscripten) {
        const glfw_lib = zglfw.artifact("glfw");
        engine_lib.linkLibrary(glfw_lib);
    }

    // OpenGL bindings
    const zopengl = b.dependency("zopengl", .{ .target = target });
    const gl_mod = zopengl.module("root");
    engine_mod.addImport("zopengl", gl_mod);

    // Flecs
    // const zflecs = b.dependency("zflecs", .{ .target = target });
    // const zflecs_mod = zflecs.module("root");
    // engine_mod.addImport("zflecs", zflecs_mod);
    // const flecs_lib = zflecs.artifact("flecs");
    // addArchIncludes(b, target, optimize, flecs_lib) catch unreachable;
    // target_lib.linkLibrary(flecs_lib);

    // Stbi
    const zstbi = b.dependency("zstbi", .{ .target = target });
    const zstbi_mod = zstbi.module("root");
    engine_mod.addImport("zstbi", zstbi_mod);

    // Math
    const zmath = b.dependency("zmath", .{ .target = target });
    const math_mod = zmath.module("root");
    engine_mod.addImport("zmath", math_mod);

    // GUI
    // const zgui = b.dependency("zgui", .{
    //     .target = target,
    //     .backend = .glfw_opengl3,
    // });
    // const zgui_mod = zgui.module("root");
    // engine_mod.addImport("zgui", zgui_mod);
    // const gui_lib = zgui.artifact("imgui");
    // addArchIncludes(b, target, optimize, gui_lib) catch unreachable;
    // target_lib.linkLibrary(gui_lib);

    // Lua
    // const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
    // ziglua.module("ziglua").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    // ziglua.module("ziglua-c").addIncludePath(.{ .cwd_relative = "/home/jeffdw/.cache/emscripten/sysroot/include" });
    // const ziglua_mod = ziglua.module("ziglua");
    // const ziglua_c_mod = ziglua.module("ziglua-c");
    // engine_mod.addImport("ziglua", ziglua_mod);
    // engine_mod.addImport("ziglua-c", ziglua_c_mod);
    // const lua_lib = ziglua.artifact("lua");
    // addArchIncludes(b, target, optimize, lua_lib) catch unreachable;
    // engine_lib.linkLibrary(lua_lib);

    return .{ .engine_lib = engine_lib, .engine_mod = engine_mod };
}

pub fn buildGame(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_dep: *std.Build.Dependency,
    engine_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    assets: []const []const u8,
) *std.Build.Step {
    // Create the engine library
    const engine_lib: ?*std.Build.Step.Compile = blk: {
        if (target.result.os.tag != .emscripten) {
            break :blk engine_dep.artifact("engine");
        } else {
            break :blk null;
        }
    };

    return buildExample(
        b,
        target,
        optimize,
        engine_lib,
        engine_mod,
        name,
        exe_mod,
        assets,
    );
}

// This one is internal since it uses the engine lib from our internal build step.
fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    engine_lib: ?*std.Build.Step.Compile,
    engine_mod: *std.Build.Module,
    name: []const u8,
    exe_mod: *std.Build.Module,
    assets: []const []const u8,
) *std.Build.Step {
    _ = optimize;

    const exe = blk: {
        if (target.result.os.tag == .emscripten) {
            break :blk b.addStaticLibrary(.{
                .name = name,
                .root_module = exe_mod,
            });
        } else {
            break :blk b.addExecutable(.{
                .name = name,
                .root_module = exe_mod,
            });
        }
    };

    // Add the engine as an import to the example.
    exe_mod.addImport("engine", engine_mod);

    // Add necessary C linkage
    exe.linkLibC();

    // Handle platform-specific linking
    switch (target.result.os.tag) {
        .emscripten => {
            const path = b.pathJoin(&.{ b.install_prefix, "web", name });
            const index_path = b.pathJoin(&.{ path, "index.html" });

            const mkdir_command = b.addSystemCommand(&[_][]const u8{"mkdir"});
            mkdir_command.addArgs(&.{ "-p", path });

            const emcc_exe_path = "/usr/lib/emscripten/em++";
            const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_exe_path});

            emcc_command.step.dependOn(&mkdir_command.step);
            emcc_command.addArgs(&[_][]const u8{
                "-o",
                index_path,
                "-sFULL-ES3=1",
                "-sUSE_GLFW=3",
                "-O3",
                "-g",
                "-sASYNCIFY",
                "-sMIN_WEBGL_VERSION=2",
                "-sINITIAL_MEMORY=167772160",
                "-sALLOW_MEMORY_GROWTH=1",
                //"-sMALLOC=emmalloc",
                "-sUSE_OFFSET_CONVERTER",
                "-sSUPPORT_LONGJMP=1",
                "-sERROR_ON_UNDEFINED_SYMBOLS=1",
                "-sSTACK_SIZE=2mb",
                "-sEXPORT_ALL=1",
                "--shell-file",
                b.path("src/shell.html").getPath(b),
            });

            // Add all of the specified assets
            for (assets) |asset| {
                emcc_command.addArgs(&[_][]const u8{ "--preload-file", b.pathJoin(&.{ assets_dir, asset }) });
            }

            emcc_command.addFileArg(exe.getEmittedBin());
            // emcc_command.addFileArg(engine_lib.getEmittedBin());

            // We setup the engine in an emscripten build to output a `web/engine.o` to link against
            const obj_path = engine_mod.owner.getInstallPath(
                .prefix,
                "web/engine.o",
            );
            emcc_command.addArg(obj_path);

            // const zgui = b.dependency("zgui", .{
            //     .target = target,
            //     .backend = .glfw_opengl3,
            // });
            // const gui_lib = zgui.artifact("imgui");
            // emcc_command.addFileArg(gui_lib.getEmittedBin());

            // // Lua
            // const ziglua = b.dependency("ziglua", .{ .target = target, .optimize = optimize, .lang = .lua53 });
            // const lua_lib = ziglua.artifact("lua");
            // emcc_command.addFileArg(lua_lib.getEmittedBin());

            emcc_command.step.dependOn(&exe.step);
            return &emcc_command.step;
        },
        else => {
            exe.linkLibrary(engine_lib.?);

            const path = b.pathJoin(&.{ "bin", name });

            const install_content_step = b.addInstallDirectory(.{
                .source_dir = b.path(assets_dir),
                .install_dir = .{ .custom = path },
                .install_subdir = "assets",
                .include_extensions = assets,
            });
            exe.step.dependOn(&install_content_step.step);

            const install_ex = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = path } } });

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.setCwd(.{ .cwd_relative = b.pathJoin(&.{ b.install_prefix, path }) });
            run_cmd.step.dependOn(&install_ex.step);

            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step(name, "Run example");
            run_step.dependOn(&run_cmd.step);
            return &install_ex.step;
        },
    }
}
