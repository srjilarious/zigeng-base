const std = @import("std");
const builtin = @import("builtin");
const engine = @import("engine");
const glfw = engine.glfw;
const gl = engine.gl;

const math = @import("zmath");
const EngOptions = engine.EngineOptions;

// Sets up the panic handler and log handler depending on the OS target.
pub const panic = engine.system.panic;
pub const std_options = engine.system.std_options;

const AppRunner = engine.AppRunner(App, .{});

pub const App = struct {
    testVal: i32,

    pub fn init(val: i32) App {
        return .{
            .testVal = val,
        };
    }

    pub fn deinit(self: *App) void {
        _ = self;
    }

    pub fn update(self: *App, eng: *AppRunner.EngineInst, delta: f64) bool {
        _ = self;
        _ = delta;
        if (eng.window.getKey(.one) == .press) std.debug.print("one!\n", .{});

        if (eng.window.getKey(.escape) == .press) {
            return false;
        }
        return true;
    }

    pub fn render(self: *App, eng: *AppRunner.EngineInst) void {
        _ = self;
        _ = eng;
        gl.clearColor(0.2, 0.2, 0.9, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);
    }
};

pub fn main() !void {
    std.log.info("Game Loop Example", .{});
    const alloc = std.heap.c_allocator;
    const appRunner = try AppRunner.init("Game Loop Example.", alloc, .{});
    var app = App.init(123);

    glfw.swapInterval(0);
    appRunner.run(&app);
}
