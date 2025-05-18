const std = @import("std");
const builtin = @import("builtin");

pub const glfw = @import("zglfw");
pub const stbi = @import("zstbi");

const zopengl = @import("zopengl");
pub const gl = zopengl.bindings;
pub const zmath = @import("zmath");

pub const system = @import("./system.zig");

pub const Vec2I = struct {
    x: i32,
    y: i32,
};

pub const EngineOptions = struct {
    comptimeCheck: bool = false,
};

pub const EngineInitOptions = struct {
    fullscreen: bool = false,
    windowSize: Vec2I = .{ .x = 800, .y = 600 },
};

pub const web = if (builtin.os.tag == .emscripten) @import("./web.zig") else {};

// Globals used by AppRunner main loop in emscripten for web builds.
var g_EmscriptenRunnerRef: ?*anyopaque = null;
var g_EmscriptenAppRef: ?*anyopaque = null;

pub fn AppRunner(comptime AppData: type, comptime engOpts: EngineOptions) type {
    const AppStruct = struct {
        pub const EngineInst = Engine(engOpts);

        const UpdateStepUs: f64 = 1.0 / 120.0;

        engine: *EngineInst,
        alloc: std.mem.Allocator,
        lag: f64 = 0,
        currTime: f64 = 0,

        const Self = @This();

        pub fn init(
            title: [:0]const u8,
            alloc: std.mem.Allocator,
            engInitOpts: EngineInitOptions,
        ) !*Self {
            var appRunner = try alloc.create(Self);
            appRunner.engine = try EngineInst.init(title, alloc, engInitOpts);
            appRunner.alloc = alloc;
            appRunner.currTime = glfw.getTime();
            return appRunner;
        }

        pub fn deinit(self: *Self) void {
            self.engine.deinit();
            self.alloc.destroy(self);
        }

        pub fn gameLoopCore(self: *Self, app: *AppData) bool {
            const newCurrTime = glfw.getTime();
            const delta = newCurrTime - self.currTime;
            self.lag += delta;
            self.currTime = newCurrTime;

            glfw.pollEvents();

            while (self.lag > UpdateStepUs) {
                self.lag -= UpdateStepUs;

                if (!app.update(self.engine, UpdateStepUs)) {
                    return false;
                }
            }

            app.render(self.engine);
            self.engine.window.swapBuffers();
            return true;
        }

        pub fn gameLoop(self: *Self, app: *AppData) void {
            // Main loop
            while (!self.engine.window.shouldClose()) {
                if (!self.gameLoopCore(app)) return;
            }
        }

        export fn mainLoop() void {
            const appRunner: *Self = @ptrCast(@alignCast(g_EmscriptenRunnerRef.?));
            const app: *AppData = @ptrCast(@alignCast(g_EmscriptenAppRef.?));
            _ = appRunner.gameLoopCore(app);
        }

        pub fn run(self: *Self, app: *AppData) void {
            std.log.info("Starting main loop...\n", .{});
            if (builtin.target.os.tag == .emscripten) {
                g_EmscriptenRunnerRef = @constCast(self);
                g_EmscriptenAppRef = @constCast(app);
                web.setMainLoop(mainLoop, null, false);
            } else {
                self.gameLoop(app);
                app.deinit();
                self.deinit();
            }
        }
    };

    return AppStruct;
}

pub fn Engine(comptime engOpts: EngineOptions) type {
    return struct {
        window: *glfw.Window,
        options: EngineInitOptions,
        scaleFactor: f32,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(title: [:0]const u8, allocator: std.mem.Allocator, options: EngineInitOptions) !*Self {
            try glfw.init();

            std.log.debug("GLFW initialized.\n", .{});

            const gl_major, const gl_minor = blk: {
                if (builtin.target.os.tag == .emscripten) {
                    break :blk .{ 2, 0 };
                } else {
                    break :blk .{ 4, 5 };
                }
            };

            if (engOpts.comptimeCheck) {
                std.log.warn("This only runs if our compile time option was, otherwise it's never compiled in!", .{});
            }

            glfw.windowHint(.context_version_major, gl_major);
            glfw.windowHint(.context_version_minor, gl_minor);

            glfw.windowHint(.opengl_profile, .opengl_core_profile);
            glfw.windowHint(.opengl_forward_compat, true);
            glfw.windowHint(.client_api, .opengl_api);
            glfw.windowHint(.doublebuffer, true);
            glfw.windowHint(.resizable, false);

            const monitor = blk: {
                if (options.fullscreen) {
                    break :blk glfw.Monitor.getPrimary();
                } else {
                    break :blk null;
                }
            };
            const window = try glfw.Window.create(options.windowSize.x, options.windowSize.y, title, monitor);
            window.setSizeLimits(400, 400, -1, -1);

            glfw.makeContextCurrent(window);
            glfw.swapInterval(1);

            std.log.info("Loading OpenGL profile.", .{});
            if (builtin.target.os.tag == .emscripten) {
                try zopengl.loadEsProfile(glfw.getProcAddress, gl_major, gl_minor);
                try zopengl.loadEsExtension(glfw.getProcAddress, .OES_vertex_array_object);
            } else {
                try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);
            }

            const glVersion = gl.getString(gl.VERSION);
            const glslVersion = gl.getString(gl.SHADING_LANGUAGE_VERSION);

            std.log.info("GL Version: {s}", .{glVersion});
            std.log.info("GLSL Version: {s}", .{glslVersion});

            const scale_factor = scale_factor: {
                const scale = window.getContentScale();
                break :scale_factor @max(scale[0], scale[1]);
            };

            std.log.debug("Initializing STBI.", .{});
            stbi.init(allocator);

            std.log.info("Engine Initialized.", .{});

            const eng = try allocator.create(Self);
            eng.* = .{
                .window = window,
                .options = options,
                .scaleFactor = scale_factor,
                .allocator = allocator,
            };
            return eng;
        }

        pub fn deinit(self: *Self) void {
            stbi.deinit();

            self.window.destroy();
            glfw.terminate();

            self.allocator.destroy(self);
        }
    };
}
