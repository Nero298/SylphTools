// luau_bridge.cpp
//
// A minimal extern "C" bridge around Luau's VM + Compiler, built as a
// shared library so Dart's `dart:ffi` can call into it directly (Dart FFI
// only understands plain C ABI, not C++ name-mangled symbols).
//
// Design: unlike the original one-shot version of this file, sessions are
// now HANDLE-BASED and stay alive across calls. This is required for the
// GUI preview feature — a script that does
//   button.MouseButton1Click:Connect(function() ... end)
// stores a Luau closure that needs to still exist (with its captured
// upvalues) when the user later taps that button in the Flutter preview.
// That means the lua_State can't be closed right after the script runs;
// it's kept around in a registry until the Dart side explicitly disposes
// it (e.g. when leaving the Script Runner screen, or before running a new
// script).
//
// Every session also has the mock Roblox GUI API (see
// sylph_gui_bootstrap.lua, embedded below as a raw string) loaded into it
// BEFORE the user's script, so `Instance.new`, `game`, `workspace`, UDim2,
// Color3, etc. all resolve to something sane instead of erroring out.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sstream>
#include <unordered_map>
#include <mutex>
#include <atomic>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "luacode.h"
}

namespace {

// ── Embedded GUI bootstrap source ───────────────────────────────────
// Kept as a plain C++ raw string so there's no dependency on reading an
// asset file off disk at runtime (which would need Android asset APIs
// wired through JNI). If you edit native/luau_wrapper/sylph_gui_bootstrap.lua,
// paste the updated contents in here too — the two are meant to stay
// byte-for-byte identical; the .lua file exists purely for editing with
// Luau syntax highlighting.
#include "sylph_gui_bootstrap_embedded.h"

constexpr int kMaxInstructionsBeforeAbort = 100'000'000;

// ── Per-session state ────────────────────────────────────────────────
struct LuauSession
{
    lua_State* L = nullptr;
    std::ostringstream output;
    long long instructionCount = 0;
    bool timedOut = false;
};

std::mutex g_sessionsMutex;
std::unordered_map<int64_t, LuauSession*> g_sessions;
std::atomic<int64_t> g_nextHandle{1};

// Luau calls the interrupt/print callbacks with only a lua_State*, so we
// stash the owning LuauSession* on each thread via lua_setthreaddata and
// retrieve it with lua_getthreaddata inside the callbacks.
void bridge_interrupt(lua_State* L, int gc)
{
    if (gc >= 0)
        return; // GC safepoint, not a normal instruction tick — never raise from here

    auto* session = static_cast<LuauSession*>(lua_getthreaddata(L));
    if (!session)
        return;

    session->instructionCount++;
    if (session->instructionCount > kMaxInstructionsBeforeAbort)
    {
        session->timedOut = true;
        lua_pushstring(L, "Script exceeded the instruction limit (possible infinite loop)");
        lua_error(L);
    }
}

int bridge_print(lua_State* L)
{
    auto* session = static_cast<LuauSession*>(lua_getthreaddata(L));
    int n = lua_gettop(L);
    for (int i = 1; i <= n; ++i)
    {
        size_t len = 0;
        const char* s = luaL_tolstring(L, i, &len);
        if (session)
        {
            if (i > 1)
                session->output << '\t';
            session->output.write(s, static_cast<std::streamsize>(len));
        }
        lua_pop(L, 1); // pop the string pushed by luaL_tolstring
    }
    if (session)
        session->output << '\n';
    return 0;
}

LuauSession* find_session(int64_t handle)
{
    std::lock_guard<std::mutex> lock(g_sessionsMutex);
    auto it = g_sessions.find(handle);
    return it == g_sessions.end() ? nullptr : it->second;
}

// Runs sylph_gui_bootstrap_src on a freshly-created lua_State. Returns
// false (with a message) only if the bootstrap itself fails to
// compile/run, which would indicate a bug in the bootstrap script, not
// anything the user's script did.
bool run_bootstrap(lua_State* L, LuauSession* session, std::string* errorOut)
{
    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(sylph_gui_bootstrap_src, strlen(sylph_gui_bootstrap_src), nullptr, &bytecodeSize);
    if (!bytecode)
    {
        *errorOut = "Internal error: GUI bootstrap failed to compile";
        return false;
    }

    int loadResult = luau_load(L, "=sylph_gui_bootstrap", bytecode, bytecodeSize, 0);
    free(bytecode);
    if (loadResult != 0)
    {
        size_t len = 0;
        const char* err = lua_tolstring(L, -1, &len);
        *errorOut = std::string("Internal error: GUI bootstrap load failed: ") + (err ? std::string(err, len) : "unknown");
        lua_pop(L, 1);
        return false;
    }

    // Same ordering fix as in sylph_luau_run_in_session below: the thread
    // lua_newthread pushes must be swapped below the chunk before moving,
    // or lua_xmove moves the thread object instead of the chunk function.
    lua_State* co = lua_newthread(L);
    lua_setthreaddata(co, session);
    lua_insert(L, -2);   // [thread, chunk] -> chunk now on top
    lua_xmove(L, co, 1); // move the chunk onto co's stack
    lua_pop(L, 1);       // pop the now-empty thread slot left on L's stack

    int callResult = lua_resume(co, L, 0);

    if (callResult != LUA_OK)
    {
        size_t len = 0;
        const char* err = lua_tolstring(co, -1, &len);
        *errorOut = std::string("Internal error: GUI bootstrap runtime error: ") + (err ? std::string(err, len) : "unknown");
        return false;
    }
    return true;
}

} // namespace

extern "C" {

// Creates a new session (fresh Luau state + GUI bootstrap loaded) and
// returns an opaque handle. Returns 0 on failure.
int64_t sylph_luau_create()
{
    lua_State* L = luaL_newstate();
    if (!L)
        return 0;

    luaL_openlibs(L);

    auto* session = new LuauSession();
    session->L = L;
    lua_setthreaddata(L, session);

    lua_pushcfunction(L, bridge_print, "print");
    lua_setglobal(L, "print");

    std::string bootstrapError;
    if (!run_bootstrap(L, session, &bootstrapError))
    {
        // Bootstrap failing is our bug, not the user's — but rather than
        // crash, hand back a session that will simply report this error
        // on every run, so the app stays usable and the message is visible.
        session->output << "[bootstrap error] " << bootstrapError << '\n';
    }

    int64_t handle = g_nextHandle.fetch_add(1);
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        g_sessions[handle] = session;
    }
    return handle;
}

// Compiles and runs `source` inside the session identified by `handle`.
// The session's lua_State stays open afterwards — any GUI callbacks the
// script registered via :Connect remain live for later sylph_luau_fire_event
// calls. Returns a newly-allocated string the caller MUST free with
// sylph_luau_free():
//   "OK\n<stdout output>"                     on success
//   "ERROR\n<compiler or runtime error text>"  on failure
const char* sylph_luau_run_in_session(int64_t handle, const char* source)
{
    LuauSession* session = find_session(handle);
    if (!session)
        return strdup("ERROR\nInvalid or disposed session handle");

    lua_State* L = session->L;
    session->output.str("");
    session->output.clear();
    session->instructionCount = 0;
    session->timedOut = false;

    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source, strlen(source), nullptr, &bytecodeSize);

    std::string result;

    if (!bytecode)
    {
        result = "ERROR\nFailed to compile script (compiler returned no bytecode)";
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
        lua_pop(L, 1); // pop the error message
        return strdup(result.c_str());
    }

    luaL_sandbox(L);

    // IMPORTANT: lua_newthread(L) pushes the new thread itself onto L's
    // stack, ON TOP OF the chunk function that luau_load just pushed. So
    // at this point L's stack (bottom to top) is: [chunk, thread]. Moving
    // "1" value from L to co with lua_xmove would move the THREAD, not the
    // chunk — which is exactly the "attempt to call a thread value" bug
    // this used to have. lua_insert(L, -2) swaps them so the chunk ends up
    // on top, and *that's* what gets moved onto co's stack.
    lua_State* co = lua_newthread(L);
    lua_setthreaddata(co, session);
    lua_insert(L, -2);   // stack is now: [thread, chunk] — chunk on top
    lua_xmove(L, co, 1); // move the chunk function onto co's stack
    lua_pop(L, 1);       // pop the now-empty thread slot left on L's stack

    lua_Callbacks* cb = lua_callbacks(co);
    cb->interrupt = bridge_interrupt;

    int callResult = lua_resume(co, L, 0);

    if (callResult != LUA_OK)
    {
        size_t len = 0;
        const char* err = lua_tolstring(co, -1, &len);
        result = "ERROR\n";
        result += (err ? std::string(err, len) : "Unknown runtime error");
        if (!session->output.str().empty())
        {
            result += "\n--- output before error ---\n";
            result += session->output.str();
        }
        return strdup(result.c_str());
    }

    result = "OK\n";
    result += session->output.str();
    return strdup(result.c_str());
}

// Returns a JSON string describing the current GUI tree (everything
// parented, directly or transitively, under PlayerGui). Caller MUST free
// with sylph_luau_free(). Returns "[]" if the session is invalid.
const char* sylph_luau_snapshot(int64_t handle)
{
    LuauSession* session = find_session(handle);
    if (!session)
        return strdup("[]");

    lua_State* L = session->L;
    lua_getglobal(L, "__sylph_dump");
    if (!lua_isfunction(L, -1))
    {
        lua_pop(L, 1);
        return strdup("[]");
    }

    int callResult = lua_pcall(L, 0, 1, 0);
    if (callResult != LUA_OK)
    {
        lua_pop(L, 1); // pop error message
        return strdup("[]");
    }

    size_t len = 0;
    const char* json = lua_tolstring(L, -1, &len);
    std::string result(json ? json : "[]", json ? len : 2);
    lua_pop(L, 1);
    return strdup(result.c_str());
}

// Invokes the Luau callback(s) connected (via :Connect) to `eventName` on
// the instance with id `instanceId` — e.g. tapping a button in the Flutter
// preview calls this with (that button's id, "MouseButton1Click"). After
// firing, the caller should re-fetch a snapshot since the callback may
// have changed properties (e.g. updated a TextLabel's Text).
// Returns "OK" or "ERROR\n<message>" — caller MUST free with sylph_luau_free().
const char* sylph_luau_fire_event(int64_t handle, int64_t instanceId, const char* eventName)
{
    LuauSession* session = find_session(handle);
    if (!session)
        return strdup("ERROR\nInvalid or disposed session handle");

    lua_State* L = session->L;
    lua_getglobal(L, "__sylph_fire");
    if (!lua_isfunction(L, -1))
    {
        lua_pop(L, 1);
        return strdup("ERROR\nGUI bootstrap not loaded");
    }

    lua_pushnumber(L, static_cast<double>(instanceId));
    lua_pushstring(L, eventName);

    int callResult = lua_pcall(L, 2, 1, 0);
    if (callResult != LUA_OK)
    {
        size_t len = 0;
        const char* err = lua_tolstring(L, -1, &len);
        std::string result = "ERROR\n";
        result += (err ? std::string(err, len) : "Unknown error firing event");
        lua_pop(L, 1);
        return strdup(result.c_str());
    }

    size_t len = 0;
    const char* out = lua_tolstring(L, -1, &len);
    std::string result(out ? out : "OK", out ? len : 2);
    lua_pop(L, 1);
    return strdup(result.c_str());
}

// Closes and forgets a session. Safe to call with an already-disposed or
// invalid handle (no-op).
void sylph_luau_dispose(int64_t handle)
{
    LuauSession* session = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_sessionsMutex);
        auto it = g_sessions.find(handle);
        if (it == g_sessions.end())
            return;
        session = it->second;
        g_sessions.erase(it);
    }
    lua_close(session->L);
    delete session;
}

// Convenience one-shot entry point for callers that don't need the GUI
// preview or persistent state (e.g. the UNC Checker, which just wants a
// quick "does this print OK or MISSING" per snippet). Internally this is
// just create + run + dispose, so it does NOT leak sessions even though
// it's built on top of the handle-based API.
const char* sylph_luau_run(const char* source)
{
    int64_t handle = sylph_luau_create();
    if (handle == 0)
        return strdup("ERROR\nFailed to create Luau state (out of memory?)");

    const char* result = sylph_luau_run_in_session(handle, source);
    sylph_luau_dispose(handle);
    return result;
}

// Frees a string previously returned by any sylph_luau_* function above.
// Dart's FFI finalizer calls this — without it, every call would leak.
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
