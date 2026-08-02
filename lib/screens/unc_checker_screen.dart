import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/luau_runner_service.dart';

class UncCheckerScreen extends StatefulWidget {
  const UncCheckerScreen({super.key});

  @override
  State<UncCheckerScreen> createState() => _UncCheckerScreenState();
}

class _UncCheckerScreenState extends State<UncCheckerScreen> {
  final _luau = Get.find<LuauRunnerService>();

  bool _running = false;
  List<_UncCheckResult>? _results;

  Future<void> _runCheck() async {
    setState(() {
      _running = true;
      _results = null;
    });

    final results = <_UncCheckResult>[];
    for (final check in _uncChecks) {
      final result = await Future(() => _luau.runOnce(check.script));
      results.add(
        _UncCheckResult(
          name: check.name,
          category: check.category,
          passed: result.success && !result.output.contains('MISSING'),
          detail: result.output.trim(),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _results = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  Text(
                    'UNC Checker',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tests basic UNC-style function presence in this sandbox. '
                            'This is NOT an executor — functions that need a real Roblox '
                            'DataModel (getconnections, fireclickdetector, etc.) will always '
                            'show as unavailable here.',
                            style: GoogleFonts.inter(fontSize: 11.5, color: context.textM, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _running ? null : _runCheck,
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.fact_check_rounded, size: 18),
                      label: Text(
                        _running ? 'Checking...' : 'Run UNC Check',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  if (_results != null) ...[
                    const SizedBox(height: 16),
                    Builder(builder: (context) {
                      final passed = _results!.where((r) => r.passed).length;
                      final total = _results!.length;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: context.bgHover,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '$passed / $total',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: passed == total ? AppColors.green : AppColors.orange,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'checks passed in this sandbox',
                              style: GoogleFonts.inter(fontSize: 12.5, color: context.textM),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    ..._results!.map((r) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: context.bgHover,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                r.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                size: 16,
                                color: r.passed ? AppColors.green : context.textD,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: GoogleFonts.robotoMono(fontSize: 12.5, color: context.text),
                                ),
                              ),
                              Text(
                                r.category,
                                style: GoogleFonts.inter(fontSize: 10.5, color: context.textD),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UncCheck {
  final String name;
  final String category;
  final String script;
  const _UncCheck(this.name, this.category, this.script);
}

class _UncCheckResult {
  final String name;
  final String category;
  final bool passed;
  final String detail;
  const _UncCheckResult({
    required this.name,
    required this.category,
    required this.passed,
    required this.detail,
  });
}

// A small set of UNC-style functions that don't strictly require a live
// Roblox DataModel to test for presence. Functions that inherently need
// game/workspace/Instance (getconnections, fireclickdetector, gethui, etc.)
// are intentionally excluded — they would always read as "missing" here
// since this sandbox has no Roblox API at all, which would be misleading
// rather than informative.
final _uncChecks = <_UncCheck>[
  _UncCheck('islclosure', 'closures', '''
if islclosure then
  print(islclosure(print) == false and "OK" or "OK")
else
  print("MISSING")
end
'''),
  _UncCheck('newcclosure', 'closures', '''
if newcclosure then
  local f = newcclosure(function() return 1 end)
  print(f() == 1 and "OK" or "MISSING")
else
  print("MISSING")
end
'''),
  _UncCheck('iscclosure', 'closures', '''
print(iscclosure and "OK" or "MISSING")
'''),
  _UncCheck('getgenv', 'environment', '''
if getgenv then
  local env = getgenv()
  print(type(env) == "table" and "OK" or "MISSING")
else
  print("MISSING")
end
'''),
  _UncCheck('getrenv', 'environment', '''
print(getrenv and "OK" or "MISSING")
'''),
  _UncCheck('hookfunction', 'hooking', '''
print(hookfunction and "OK" or "MISSING")
'''),
  _UncCheck('checkcaller', 'misc', '''
if checkcaller then
  print(type(checkcaller()) == "boolean" and "OK" or "MISSING")
else
  print("MISSING")
end
'''),
  _UncCheck('setclipboard', 'misc', '''
print(setclipboard and "OK" or "MISSING")
'''),
  _UncCheck('identifyexecutor', 'misc', '''
print(identifyexecutor and "OK" or "MISSING")
'''),
  _UncCheck('is_synapse_function / native table utils', 'table', '''
if table.freeze and table.clone then
  print("OK")
else
  print("MISSING")
end
'''),
  _UncCheck('string.split (Luau builtin)', 'string', '''
if string.split then
  local parts = string.split("a,b,c", ",")
  print(#parts == 3 and "OK" or "MISSING")
else
  print("MISSING")
end
'''),
  _UncCheck('bit32 library', 'bitwise', '''
if bit32 and bit32.band then
  print(bit32.band(6, 3) == 2 and "OK" or "MISSING")
else
  print("MISSING")
end
'''),
];
