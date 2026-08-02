// luau_bridge.cpp
//
// A minimal extern "C" bridge around Luau's VM + Compiler, built as a
// shared library so Dart's `dart:ffi` can call into it directly (Dart FFI
// only understands plain C ABI, not C++ name-mangled symbols).
//
// Design: each call to sylph_luau_run() creates a brand-new Luau state,
// runs the script to completion (or until it errors / times out via
// instruction count), captures anything the script printed via `print()`,
// and returns everything as a single formatted string. This keeps the
// bridge stateless and simple — there's no persistent VM between calls,
// which is fine for a "run this script and show me the output" tool.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sstream>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "luacode.h"
}

namespace {

// Accumulates everything printed by the running script via `print()`.
// Thread-local so concurrent calls (if the Dart side ever runs two at
// once on different threads) don't interleave output.
thread_local std::ostringstream g_output;

// Custom `print` — Luau's stdlib print writes to stdout by default,
// which is useless inside an embedded Android library. Redirect it into
// our buffer instead.
int bridge_print(lua_State* L)
{
    int n = lua_gettop(L);
    for (int i = 1; i <= n; ++i)
    {
        size_t len = 0;
        const char* s = luaL_tolstring(L, i, &len);
        if (i > 1)
            g_output << '\t';
        g_output.write(s, static_cast<std::streamsize>(len));
        lua_pop(L, 1); // pop the string pushed by luaL_tolstring
    }
    g_output << '\n';
    return 0;
}

// Simple instruction-count based watchdog so an accidental `while true do end`
// in a test script can't hang the whole app forever. Luau calls this
// periodically via lua_callbacks(L)->interrupt.
constexpr int kMaxInstructionsBeforeAbort = 100'000'000;
thread_local long long g_instructionCount = 0;
thread_local bool g_timedOut = false;

void bridge_interrupt(lua_State* L, int /*gc*/)
{
    g_instructionCount++;
    if (g_instructionCount > kMaxInstructionsBeforeAbort)
    {
        g_timedOut = true;
        luaL_error(L, "Script exceeded the instruction limit (possible infinite loop)");
    }
}

} // namespace

extern "C" {

// Runs a Luau script and returns a newly-allocated C string describing the
// result. Caller MUST free the returned pointer with sylph_luau_free().
//
// Output format (all in one string, sections separated by a NUL-free marker
// so Dart can split on it):
//   "OK\n<stdout output>"                     on success
//   "ERROR\n<compiler or runtime error text>" on failure
const char* sylph_luau_run(const char* source)
{
    g_output.str("");
    g_output.clear();
    g_instructionCount = 0;
    g_timedOut = false;

    lua_State* L = luaL_newstate();
    if (!L)
    {
        const char* msg = "ERROR\nFailed to create Luau state (out of memory?)";
        return strdup(msg);
    }

    luaL_openlibs(L);

    // Override print to capture output instead of writing to stdout.
    lua_pushcfunction(L, bridge_print, "print");
    lua_setglobal(L, "print");

    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source, strlen(source), nullptr, &bytecodeSize);

    std::string result;

    if (!bytecode)
    {
        result = "ERROR\nFailed to compile script (compiler returned no bytecode)";
        lua_close(L);
        return strdup(result.c_str());
    }

    int loadResult = luau_load(L, "=script", bytecode, bytecodeSize, 0);
    free(bytecode);

    if (loadResult != 0)
    {
        size_t len = 0;
        const char* err = lua_tolstring(L, -1, &len);
        result = "ERROR\n";
        result += (err ? std::string(err, len) : "Unknown load error");
        lua_close(L);
        return strdup(result.c_str());
    }

    // Sandbox the global state so scripts can't monkey-patch stdlib
    // functions in ways that would carry over — not that state carries
    // over between calls here, but this also enables some VM optimizations.
    luaL_sandbox(L);

    // Luau's main chunk is invoked as a coroutine via lua_resume — unlike
    // stock Lua where you'd typically lua_pcall the loaded chunk directly.
    lua_State* co = lua_newthread(L);
    luaL_sandboxthread(co);
    lua_xmove(L, co, 1); // move the loaded chunk function onto the new thread's stack

    // Wire up the instruction-count watchdog on the executing thread.
    lua_Callbacks* cb = lua_callbacks(co);
    cb->interrupt = bridge_interrupt;

    int callResult = lua_resume(co, L, 0);

    if (callResult != LUA_OK)
    {
        size_t len = 0;
        const char* err = lua_tolstring(co, -1, &len);
        result = "ERROR\n";
        result += (err ? std::string(err, len) : "Unknown runtime error");
        if (!g_output.str().empty())
        {
            result += "\n--- output before error ---\n";
            result += g_output.str();
        }
        lua_close(L);
        return strdup(result.c_str());
    }

    result = "OK\n";
    result += g_output.str();

    lua_close(L);
    return strdup(result.c_str());
}

// Frees a string previously returned by sylph_luau_run(). Dart's FFI
// finalizer calls this — without it, every run() call would leak memory.
void sylph_luau_free(const char* ptr)
{
    free(const_cast<char*>(ptr));
}

// Returns a version string, mostly useful for a "Powered by Luau" credit
// line in Settings. Luau doesn't always expose LUA_VERSION the same way
// stock Lua does, so this is intentionally a fixed literal rather than
// relying on a macro that may not exist under this name.
const char* sylph_luau_version()
{
    return "Luau (Roblox)";
}

} // extern "C"
