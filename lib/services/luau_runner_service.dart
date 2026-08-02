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
typedef _RunNative = Pointer<Utf8> Function(Pointer<Utf8> source);
typedef _RunDart = Pointer<Utf8> Function(Pointer<Utf8> source);

typedef _FreeNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeDart = void Function(Pointer<Utf8> ptr);

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

/// Loads `libsylph_luau.so` and exposes the native Luau runtime to Dart.
///
/// This talks to a real Luau VM compiled from Roblox's open-source
/// `luau-lang/luau` (see /native/luau_wrapper) — so it understands actual
/// Luau syntax (string interpolation, `continue`, compound assignment,
/// etc.), unlike pure-Dart Lua interpreters which only support stock Lua.
///
/// There is intentionally no Roblox API surface here (`game`, `workspace`,
/// `Instance`, etc.) — this is a plain Luau sandbox for testing logic, not
/// a Roblox emulator.
class LuauRunnerService {
  DynamicLibrary? _lib;
  _RunDart? _run;
  _FreeDart? _free;
  _VersionDart? _version;
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
    } catch (e) {
      _loadError = 'Failed to load native Luau runtime: $e';
      _lib = null;
    }
  }

  /// Compiles and runs [source] as a Luau script, returning everything the
  /// script printed (or an error message) as [LuauRunResult].
  LuauRunResult run(String source) {
    init();
    if (!isAvailable) {
      return LuauRunResult(
        success: false,
        output: _loadError ?? 'Luau runtime is not available.',
      );
    }

    final sourcePtr = source.toNativeUtf8();
    try {
      final resultPtr = _run!(sourcePtr);
      try {
        final raw = resultPtr.toDartString();
        // Native side prefixes with "OK\n" or "ERROR\n" — see luau_bridge.cpp.
        final newlineIdx = raw.indexOf('\n');
        if (newlineIdx == -1) {
          return LuauRunResult(success: false, output: raw);
        }
        final status = raw.substring(0, newlineIdx);
        final body = raw.substring(newlineIdx + 1);
        return LuauRunResult(success: status == 'OK', output: body);
      } finally {
        _free!(resultPtr);
      }
    } catch (e) {
      return LuauRunResult(success: false, output: 'FFI call failed: $e');
    } finally {
      calloc.free(sourcePtr);
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
