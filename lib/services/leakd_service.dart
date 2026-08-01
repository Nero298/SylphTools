import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of a LeakD API call. Mirrors the API's own `success` envelope so
/// the UI can branch on [success] without try/catching JSON shape mismatches.
class LeakdResult {
  final bool success;
  final String? outputCode;
  final String? error;
  final Map<String, dynamic>? fileInfo;
  final Map<String, dynamic> raw;

  LeakdResult({
    required this.success,
    this.outputCode,
    this.error,
    this.fileInfo,
    required this.raw,
  });

  factory LeakdResult.fromJson(Map<String, dynamic> json) {
    return LeakdResult(
      success: json['success'] == true,
      // Different endpoints name the code field differently
      // (obfuscated_code vs deobfuscated_code) — normalize to one field.
      outputCode:
          (json['obfuscated_code'] ?? json['deobfuscated_code'] ?? json['code'])
              as String?,
      error: json['error'] as String?,
      fileInfo: json['file'] as Map<String, dynamic>?,
      raw: json,
    );
  }

  factory LeakdResult.networkError(String message) => LeakdResult(
        success: false,
        error: message,
        raw: const {},
      );
}

/// Obfuscation presets accepted by the /obfuscate endpoint.
enum LeakdObfuscatePreset {
  robloxExecutor('RobloxExecutor'),
  robloxStudio('RobloxStudio'),
  lua51('Lua51'),
  lua52('Lua52'),
  lua53('Lua53'),
  lua54('Lua54');

  final String value;
  const LeakdObfuscatePreset(this.value);
}

/// Thin wrapper around the public LeakD API (leakd.up.railway.app).
///
/// LeakD is a free-standing REST API (not a website to scrape), so calls
/// here are plain HTTP multipart uploads — no WebView needed.
///
/// Endpoints confirmed against real responses: obfuscate, moonsec,
/// ironbrew2, prometheus, ironveil.
/// Endpoints wired by API convention but not yet response-verified:
/// detect, hercules, luaobfuscator, beautify — if the JSON shape differs,
/// only [LeakdResult.fromJson] needs adjusting, not the call sites.
class LeakdService {
  static const _baseUrl = 'https://leakd.up.railway.app';
  static const _timeout = Duration(seconds: 60);

  Future<LeakdResult> _postFile(
    String endpoint,
    String luaSource, {
    String filename = 'script.lua',
    Map<String, String>? queryParams,
  }) async {
    try {
      var uri = Uri.parse('$_baseUrl/$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            utf8.encode(luaSource),
            filename: filename,
          ),
        );

      final streamed = await request.send().timeout(_timeout);
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode >= 500) {
        return LeakdResult.networkError(
          'Server error (${streamed.statusCode}). LeakD may be down — try again shortly.',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      return LeakdResult.fromJson(json);
    } on http.ClientException {
      return LeakdResult.networkError(
        'Could not reach LeakD. Check your internet connection.',
      );
    } on FormatException {
      return LeakdResult.networkError(
        'LeakD returned an unexpected response format.',
      );
    } catch (e) {
      return LeakdResult.networkError('Unexpected error: $e');
    }
  }

  /// Obfuscate a Lua/Luau script.
  Future<LeakdResult> obfuscate(
    String luaSource, {
    LeakdObfuscatePreset preset = LeakdObfuscatePreset.robloxExecutor,
  }) {
    return _postFile(
      'obfuscate',
      luaSource,
      queryParams: {'preset': preset.value},
    );
  }

  /// Deobfuscate a MoonSec v3-protected script.
  Future<LeakdResult> deobfuscateMoonsec(String luaSource) {
    return _postFile('moonsec', luaSource);
  }

  /// Deobfuscate an IronBrew2-protected script.
  Future<LeakdResult> deobfuscateIronbrew2(String luaSource) {
    return _postFile('ironbrew2', luaSource);
  }

  /// Deobfuscate a Prometheus-protected script.
  Future<LeakdResult> deobfuscatePrometheus(String luaSource) {
    return _postFile('prometheus', luaSource);
  }

  /// Deobfuscate an IronVeil-protected script.
  Future<LeakdResult> deobfuscateIronveil(String luaSource) {
    return _postFile('ironveil', luaSource);
  }

  /// Deobfuscate a Hercules-protected script.
  Future<LeakdResult> deobfuscateHercules(String luaSource) {
    return _postFile('hercules', luaSource);
  }

  /// Deobfuscate output from luaobfuscator.com.
  Future<LeakdResult> deobfuscateLuaObfuscator(String luaSource) {
    return _postFile('luaobfuscator', luaSource);
  }

  /// Detect which obfuscator/protection a script was built with.
  Future<LeakdResult> detect(String luaSource) {
    return _postFile('detect', luaSource);
  }

  /// Beautify / pretty-print a minified or messy Lua script.
  Future<LeakdResult> beautify(String luaSource) {
    return _postFile('beautify', luaSource);
  }
}
