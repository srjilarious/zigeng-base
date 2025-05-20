This project is a stripped down version of my Zig game engine Pixzig.  It took quite a bit of messing around to get emscripten builds with GLFW, flecs, lua and ImGUI working on both native and emscripten targets.  I ran into multiple non-obvious issues and solved them usually by finding a tidbit spread around in someone else's repo or post.  I figured this might save someone else a week to have a basic starting point to build off of.

I'm writing up an article about the different issues I hit, but my main notes are:

#### Emscripten setup/build notes
- Installing `emscripten` package on Arch, puts it in `/usr/lib/empscripten`
- Had to setup cache: `embuilder.py build MINIMAL`
- Build targeting `emscripten` OS and providing a sysroot
    `zig build -Dtarget=wasm32-emscripten --sysroot /home/jeffdw/.cache/emscripten/sysroot `
- Make sure each C dependency (not Module!!) get the appropriate `addIncludePath` so that it can find emscripten's C headers.
- GLFW, need to run an ES Profile with major version 2 (on desktop I had a 4.0 core profile)
- Add `-sMIN_WEBGL_VERSION=2` in order to actually make WebGL 2 context.
- Had to change logic to be able to setup the emscripten mainloop, otherwise the page hangs.
    - This project abstracts that away in the `src/engine.zig` using the `AppRunner` structure.
- Use `std.heap.c_allocator` to be able to allocate, `std.heap.page_allocator` just crashed
    ```
    Uncaught TypeError: Cannot perform %TypedArray%.prototype.copyWithin on a detached ArrayBuffer
    at Uint8Array.copyWithin (<anonymous>)
    at __emscripten_memcpy_js (index.js:1:65127)
    at index.wasm:0x2b6e
    at index.wasm:0x5840f
    at index.wasm:0x57e13
    at index.wasm:0xbd392
    at index.wasm:0xb45b6
    at index.wasm:0xac00d
    at ret.<computed> (index.js:1:180371)
    at Module._main (index.js:1:195296)
    ```
- Use `--preload-file <blah>` (as two separate strings) in order to have files assets available to load.
- Had to load the ES extension to get glGenVertexArrays to work.
- Not having objects that are too large for the stack (SpriteBatchQueue)
  - Thanks to:
    - https://github.com/SimonLSchlee/zig15game
    - https://github.com/zig-gamedev/zig-gamedev/blob/main/samples/sdl2_demo/build.zig
    - https://github.com/zig-gamedev/zemscripten/blob/2c5c40b451a09df46a41c8f50cd2d21ec678018c/build.zig

  - Lua was really frustrating because setjmp/longjmp are translated by emcc while it compiles, so having zig build and then pass the final exe step to emcc didn't work!  Thanks to https://github.com/natecraddock/ziglua/pull/95/files#diff-f87bb3596894756629bc39d595fb18d479dc4edf168d93a911cadcb060f10fcc, realized I should just shell out to emcc for that library as well.  After that it worked!
  - Flecs was also a bit problematic:
    - Assumed the allocator!! Vendored it in the meantime to debug and figure out the issues
    - Also had a function signature mismatch on `ecs_set_id` where it thought flecs returned an `entity_t` but in fact it returns `void` as per flecs docs: https://www.flecs.dev/flecs/group__getting.html#ga6e512572fd150d2d2076972d8b97af6a
- Trying to find why rendering broken in imgui in emscripten, ended up adding debugging extension ala emscripten debugging page: https://emscripten.org/docs/porting/Debugging.html
  - Then got a stack trace: 
    Uncaught RuntimeError: null function or function signature mismatch
    at index.wasm.ImGui_ImplOpenGL3_VtxAttribState::GetState(int) (http://localhost:6931/index.wasm)
    at index.wasm.ImGui_ImplOpenGL3_RenderDrawData (imgui_impl_opengl3.cpp:531:100)
    at index.wasm.backend_glfw_opengl.draw (backend_glfw_opengl.zig:41:37)
    at index.wasm.console_test.main (console_test.zig:82:26)
    at index.wasm.main (start.zig:635:52)
    at ret.<computed> (index.js:9858:24)
    at Module._main (index.js:10814:90)
    at callMain (index.js:10909:15)
    at doRun (index.js:10948:23)
    at index.js:10957:7
- zgui had incorrect return type on `extern fn ImGui_ImplOpenGL3_Init(glsl_version: [*c]const u8) c_int;` having it return `void` which made emscripten angry.
- Had to have emcc link against the engine object rather than a static lib so that symbols weren't stripped away.
- Added a helper function to engine's build.zig so that dependent projects can easily build for whichever supported platform.
- When extacting this repo from pixzig, I left out linking the example static library against libC, zig gave an unhelpful error about unsupported architecture
    - Got the error:
    ```
    /home/jeffdw/.zvm/0.14.0/lib/std/start.zig:253:21: error: unsupported arch
            else => @compileError("unsupported arch"),
    ```
    - Had to add `exe.linkLibC();` in `buildExample`
