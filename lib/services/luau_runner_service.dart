import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Result of running a Luau script through the native runtime.
class LuauRunResult {
  final bool success;
  final String output;

  const LuauRunResult({required this.success, required this.output});
}

// ── Native function signatures ────────────────────────────────────
// One-shot (stateless) entry point — used by the UNC Checker via runOnce().
typedef _RunNative = Pointer<Utf8> Function(Pointer<Utf8> source);
typedef _RunDart = Pointer<Utf8> Function(Pointer<Utf8> source);

typedef _FreeNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeDart = void Function(Pointer<Utf8> ptr);

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

// Session-based entry points — used by the Script Runner's GUI preview,
// where the Luau VM needs to stay alive across calls so :Connect()
// callbacks registered by the user's script are still there to invoke
// when they tap a button in the preview later.
typedef _CreateNative = Int64 Function();
typedef _CreateDart = int Function();

typedef _RunInSessionNative = Pointer<Utf8> Function(Int64 handle, Pointer<Utf8> source);
typedef _RunInSessionDart = Pointer<Utf8> Function(int handle, Pointer<Utf8> source);

typedef _SnapshotNative = Pointer<Utf8> Function(Int64 handle);
typedef _SnapshotDart = Pointer<Utf8> Function(int handle);

typedef _FireEventNative = Pointer<Utf8> Function(Int64 handle, Int64 instanceId, Pointer<Utf8> eventName);
typedef _FireEventDart = Pointer<Utf8> Function(int handle, int instanceId, Pointer<Utf8> eventName);

typedef _DisposeNative = Void Function(Int64 handle);
typedef _DisposeDart = void Function(int handle);

/// Loads `libsylph_luau.so` and exposes the native Luau runtime to Dart.
///
/// This talks to a real Luau VM compiled from Roblox's open-source
/// `luau-lang/luau` (see /native/luau_wrapper) — so it understands actual
/// Luau syntax (string interpolation, `continue`, compound assignment,
/// etc.), unlike pure-Dart Lua interpreters which only support stock Lua.
///
/// Every session also has a minimal mock of the Roblox Instance/GUI API
/// preloaded (see native/luau_wrapper/sylph_gui_bootstrap.lua) — enough for
/// `Instance.new`, `game`/`workspace`/`Players`, UDim2/Color3, and
/// `:Connect()` on common GUI events to work, so scripts that build a
/// ScreenGui can be previewed instead of just erroring on nil-index.
///
/// Two ways to use this service:
///  - [runOnce] — stateless, one-shot. Good for quick checks (UNC Checker).
///  - [createSession] + [runInSession] + [snapshot] + [fireEvent] +
///    [disposeSession] — stateful. Needed for the GUI preview, since the
///    VM (and any callbacks the script registered) must stay alive between
///    "run the script" and "the user tapped a button in the preview".
class LuauRunnerService {
  DynamicLibrary? _lib;
  _RunDart? _run;
  _FreeDart? _free;
  _VersionDart? _version;
  _CreateDart? _create;
  _RunInSessionDart? _runInSession;
  _SnapshotDart? _snapshot;
  _FireEventDart? _fireEvent;
  _DisposeDart? _dispose;
  String? _loadError;

  bool get isAvailable => _lib != null && _loadError == null;
  String? get loadError => _loadError;

  void init() {
    if (_lib != null || _loadError != null) return; // already attempted

    try {
      if (!Platform.isAndroid) {
        _loadError = 'Luau runtime is only built for Android in this app.';
        return;
      }
      _lib = DynamicLibrary.open('libsylph_luau.so');
      _run = _lib!.lookupFunction<_RunNative, _RunDart>('sylph_luau_run');
      _free = _lib!.lookupFunction<_FreeNative, _FreeDart>('sylph_luau_free');
      _version =
          _lib!.lookupFunction<_VersionNative, _VersionDart>('sylph_luau_version');
      _create = _lib!.lookupFunction<_CreateNative, _CreateDart>('sylph_luau_create');
      _runInSession = _lib!
          .lookupFunction<_RunInSessionNative, _RunInSessionDart>('sylph_luau_run_in_session');
      _snapshot =
          _lib!.lookupFunction<_SnapshotNative, _SnapshotDart>('sylph_luau_snapshot');
      _fireEvent =
          _lib!.lookupFunction<_FireEventNative, _FireEventDart>('sylph_luau_fire_event');
      _dispose = _lib!.lookupFunction<_DisposeNative, _DisposeDart>('sylph_luau_dispose');
    } catch (e) {
      _loadError = 'Failed to load native Luau runtime: $e';
      _lib = null;
    }
  }

  LuauRunResult _unavailableResult() => LuauRunResult(
        success: false,
        output: _loadError ?? 'Luau runtime is not available.',
      );

  /// Splits the native "OK\n<body>" / "ERROR\n<body>" convention into a
  /// [LuauRunResult]. Shared by both the one-shot and session-based paths
  /// since the native side uses the same format for both.
  LuauRunResult _parseResult(String raw) {
    final newlineIdx = raw.indexOf('\n');
    if (newlineIdx == -1) {
      return LuauRunResult(success: false, output: raw);
    }
    final status = raw.substring(0, newlineIdx);
    final body = raw.substring(newlineIdx + 1);
    return LuauRunResult(success: status == 'OK', output: body);
  }

  /// Compiles and runs [source] in a brand-new, throwaway session — created,
  /// run, and disposed internally in one call. Use this for quick one-shot
  /// checks (like the UNC Checker's snippets) that don't need the GUI
  /// preview or any state to persist afterwards.
  LuauRunResult runOnce(String source) {
    init();
    if (!isAvailable) return _unavailableResult();

    final sourcePtr = source.toNativeUtf8();
    try {
      final resultPtr = _run!(sourcePtr);
      try {
        return _parseResult(resultPtr.toDartString());
      } finally {
        _free!(resultPtr);
      }
    } catch (e) {
      return LuauRunResult(success: false, output: 'FFI call failed: $e');
    } finally {
      calloc.free(sourcePtr);
    }
  }

  /// Creates a new persistent session and returns its handle, or `null` if
  /// the native runtime isn't available. The caller is responsible for
  /// calling [disposeSession] with this handle when done (e.g. before
  /// running a new script, or when leaving the Script Runner screen) —
  /// otherwise the underlying Luau VM leaks for the lifetime of the app
  /// process.
  int? createSession() {
    init();
    if (!isAvailable) return null;
    try {
      final handle = _create!();
      return handle == 0 ? null : handle;
    } catch (_) {
      return null;
    }
  }

  /// Compiles and runs [source] inside the session identified by [handle].
  /// The session's VM stays alive afterwards — any `:Connect()` callbacks
  /// the script registered remain invokable via [fireEvent].
  LuauRunResult runInSession(int handle, String source) {
    init();
    if (!isAvailable) return _unavailableResult();

    final sourcePtr = source.toNativeUtf8();
    try {
      final resultPtr = _runInSession!(handle, sourcePtr);
      try {
        return _parseResult(resultPtr.toDartString());
      } finally {
        _free!(resultPtr);
      }
    } catch (e) {
      return LuauRunResult(success: false, output: 'FFI call failed: $e');
    } finally {
      calloc.free(sourcePtr);
    }
  }

  /// Returns the raw JSON string describing the current GUI tree (whatever
  /// is parented under PlayerGui) for the session identified by [handle].
  /// Returns `"[]"` if the runtime isn't available or the handle is stale.
  String snapshot(int handle) {
    init();
    if (!isAvailable) return '[]';
    try {
      final resultPtr = _snapshot!(handle);
      try {
        return resultPtr.toDartString();
      } finally {
        _free!(resultPtr);
      }
    } catch (_) {
      return '[]';
    }
  }

  /// Invokes any callback(s) connected (via `:Connect`) to [eventName] on
  /// the instance with id [instanceId] inside the session identified by
  /// [handle] — e.g. call this with `("MouseButton1Click", <button id>)`
  /// when the user taps that button in the preview. Callers should fetch a
  /// fresh [snapshot] afterwards since the callback may have changed
  /// properties (e.g. updated a label's Text).
  LuauRunResult fireEvent(int handle, int instanceId, String eventName) {
    init();
    if (!isAvailable) return _unavailableResult();

    final eventPtr = eventName.toNativeUtf8();
    try {
      final resultPtr = _fireEvent!(handle, instanceId, eventPtr);
      try {
        return _parseResult(resultPtr.toDartString());
      } finally {
        _free!(resultPtr);
      }
    } catch (e) {
      return LuauRunResult(success: false, output: 'FFI call failed: $e');
    } finally {
      calloc.free(eventPtr);
    }
  }

  /// Closes and forgets the session identified by [handle]. Safe to call
  /// with an already-disposed or invalid handle.
  void disposeSession(int handle) {
    if (!isAvailable) return;
    try {
      _dispose!(handle);
    } catch (_) {
      // Best-effort — nothing sensible to do if this fails, the process
      // will reclaim the memory on exit regardless.
    }
  }

  String get version {
    init();
    if (!isAvailable || _version == null) return 'unavailable';
    try {
      return _version!().toDartString();
    } catch (_) {
      return 'unknown';
    }
  }
}
