import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../theme/app_colors.dart';
import '../services/leakd_service.dart';

enum _LuaTool {
  obfuscate('Obfuscate', Icons.enhance_photo_translate_rounded),
  moonsec('Deobfuscate MoonSec', Icons.lock_open_rounded),
  ironbrew2('Deobfuscate IronBrew2', Icons.lock_open_rounded),
  prometheus('Deobfuscate Prometheus', Icons.lock_open_rounded),
  ironveil('Deobfuscate IronVeil', Icons.lock_open_rounded),
  hercules('Deobfuscate Hercules', Icons.lock_open_rounded),
  luaobfuscator('Deobfuscate luaobfuscator.com', Icons.lock_open_rounded),
  detect('Detect Protection', Icons.search_rounded),
  beautify('Beautify / Format', Icons.auto_fix_high_rounded);

  final String label;
  final IconData icon;
  const _LuaTool(this.label, this.icon);
}

class LuaToolsScreen extends StatefulWidget {
  const LuaToolsScreen({super.key});

  @override
  State<LuaToolsScreen> createState() => _LuaToolsScreenState();
}

class _LuaToolsScreenState extends State<LuaToolsScreen> {
  final _leakd = Get.find<LeakdService>();
  final _inputCtrl = TextEditingController();

  _LuaTool _tool = _LuaTool.detect;
  LeakdObfuscatePreset _preset = LeakdObfuscatePreset.robloxExecutor;

  bool _loading = false;
  LeakdResult? _result;
  String? _pickedFileName;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lua', 'luau', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes != null) {
      setState(() {
        _inputCtrl.text = String.fromCharCodes(bytes);
        _pickedFileName = file.name;
      });
    } else if (file.path != null) {
      final content = await File(file.path!).readAsString();
      setState(() {
        _inputCtrl.text = content;
        _pickedFileName = file.name;
      });
    }
  }

  Future<void> _run() async {
    final source = _inputCtrl.text.trim();
    if (source.isEmpty) return;

    setState(() {
      _loading = true;
      _result = null;
    });

    LeakdResult result;
    switch (_tool) {
      case _LuaTool.obfuscate:
        result = await _leakd.obfuscate(source, preset: _preset);
        break;
      case _LuaTool.moonsec:
        result = await _leakd.deobfuscateMoonsec(source);
        break;
      case _LuaTool.ironbrew2:
        result = await _leakd.deobfuscateIronbrew2(source);
        break;
      case _LuaTool.prometheus:
        result = await _leakd.deobfuscatePrometheus(source);
        break;
      case _LuaTool.ironveil:
        result = await _leakd.deobfuscateIronveil(source);
        break;
      case _LuaTool.hercules:
        result = await _leakd.deobfuscateHercules(source);
        break;
      case _LuaTool.luaobfuscator:
        result = await _leakd.deobfuscateLuaObfuscator(source);
        break;
      case _LuaTool.detect:
        result = await _leakd.detect(source);
        break;
      case _LuaTool.beautify:
        result = await _leakd.beautify(source);
        break;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  void _copyResult() {
    final text = _result?.outputCode ?? _result?.raw.toString() ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  Text(
                    'Lua Tools',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'via LeakD',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.textD,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                children: [
                  // Tool selector
                  Text(
                    'Tool',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.textM,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _LuaTool.values.map((t) {
                      final selected = _tool == t;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _tool = t;
                          _result = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: 0.18)
                                : context.bgHover,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? AppColors.accentHi
                                  : Colors.transparent,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                t.icon,
                                size: 14,
                                color: selected
                                    ? AppColors.accentHi
                                    : context.textM,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                t.label,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? context.text
                                      : context.textM,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Preset selector (obfuscate only)
                  if (_tool == _LuaTool.obfuscate) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Preset',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.textM,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: context.bgHover,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LeakdObfuscatePreset>(
                          value: _preset,
                          isExpanded: true,
                          dropdownColor: context.bgPanel,
                          borderRadius: BorderRadius.circular(14),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.text,
                          ),
                          items: LeakdObfuscatePreset.values
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.value),
                                ),
                              )
                              .toList(),
                          onChanged: (p) {
                            if (p != null) setState(() => _preset = p);
                          },
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Input area
                  Row(
                    children: [
                      Text(
                        'Script',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.textM,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: Text(
                          _pickedFileName ?? 'Pick .lua file',
                          style: GoogleFonts.inter(fontSize: 12.5),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentHi,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: context.bgHover,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 10,
                      minLines: 6,
                      style: GoogleFonts.robotoMono(
                        fontSize: 12.5,
                        color: context.text,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Paste Lua/Luau source here...',
                        hintStyle: GoogleFonts.inter(color: context.textD),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _run,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Run',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),

                  // Result
                  if (_result != null) ...[
                    const SizedBox(height: 20),
                    _buildResult(context),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final result = _result!;

    if (!result.success) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.error ?? 'Unknown error',
                style: GoogleFonts.inter(fontSize: 13, color: context.text),
              ),
            ),
          ],
        ),
      );
    }

    // detect endpoint often returns metadata rather than code — show raw JSON
    final displayText = result.outputCode ??
        const JsonPrettyPrinter().tryPrint(result.raw) ??
        result.raw.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Result',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.textM,
              ),
            ),
            const Spacer(),
            if (result.fileInfo != null)
              Text(
                '${result.fileInfo!['output_size_kb'] ?? '?'} KB',
                style: GoogleFonts.inter(fontSize: 11.5, color: context.textD),
              ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: _copyResult,
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: Text('Copy', style: GoogleFonts.inter(fontSize: 12.5)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentHi,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.bgHover,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(
            displayText,
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              color: context.text,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny helper to pretty-print a JSON map without pulling in a full package.
class JsonPrettyPrinter {
  const JsonPrettyPrinter();

  String? tryPrint(Map<String, dynamic> map) {
    if (map.isEmpty) return null;
    final buf = StringBuffer();
    map.forEach((k, v) => buf.writeln('$k: $v'));
    return buf.toString().trim();
  }
}
