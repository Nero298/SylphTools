import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/luau_runner_service.dart';

class ScriptRunnerScreen extends StatefulWidget {
  const ScriptRunnerScreen({super.key});

  @override
  State<ScriptRunnerScreen> createState() => _ScriptRunnerScreenState();
}

class _ScriptRunnerScreenState extends State<ScriptRunnerScreen>
    with SingleTickerProviderStateMixin {
  final _luau = Get.find<LuauRunnerService>();
  final _codeCtrl = TextEditingController(text: _sampleScript);
  late final TabController _tabController;

  bool _running = false;
  LuauRunResult? _result;

  // UNC checker state
  bool _uncRunning = false;
  List<_UncCheckResult>? _uncResults;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _runScript() async {
    final source = _codeCtrl.text;
    setState(() {
      _running = true;
      _result = null;
    });

    // Native call is synchronous C++ under the hood; hop off the UI
    // thread briefly so a heavy script doesn't visibly freeze the frame.
    final result = await Future(() => _luau.run(source));

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _runUncCheck() async {
    setState(() {
      _uncRunning = true;
      _uncResults = null;
    });

    final results = <_UncCheckResult>[];
    for (final check in _uncChecks) {
      final result = await Future(() => _luau.run(check.script));
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
      _uncRunning = false;
      _uncResults = results;
    });
  }

  void _copyOutput() {
    final text = _result?.output ?? '';
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
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                  Text(
                    'Script Runner',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.accentHi,
              unselectedLabelColor: context.textM,
              indicatorColor: AppColors.accentHi,
              labelStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Run Script'),
                Tab(text: 'UNC Checker'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRunTab(context),
                  _buildUncTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunTab(BuildContext context) {
    return ListView(
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
                  'Plain Luau sandbox — no game, workspace, or Instance API. '
                  'Good for testing logic/algorithms, not Roblox-specific code.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: context.textM, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: context.bgHover,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _codeCtrl,
            maxLines: 14,
            minLines: 8,
            style: GoogleFonts.robotoMono(fontSize: 12.5, color: context.text, height: 1.5),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(14),
              hintText: 'Write Luau code here...',
              hintStyle: GoogleFonts.inter(color: context.textD),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _running ? null : _runScript,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(
              _running ? 'Running...' : 'Run',
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
        if (_result != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                _result!.success ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 15,
                color: _result!.success ? AppColors.green : AppColors.red,
              ),
              const SizedBox(width: 6),
              Text(
                _result!.success ? 'Output' : 'Error',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textM),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyOutput,
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text('Copy', style: GoogleFonts.inter(fontSize: 12.5)),
                style: TextButton.styleFrom(foregroundColor: AppColors.accentHi),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _result!.success
                  ? context.bgHover
                  : AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: _result!.success
                  ? null
                  : Border.all(color: AppColors.red.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              _result!.output.isEmpty ? '(no output)' : _result!.output,
              style: GoogleFonts.robotoMono(fontSize: 12, color: context.text, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUncTab(BuildContext context) {
    return ListView(
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
            onPressed: _uncRunning ? null : _runUncCheck,
            icon: _uncRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.fact_check_rounded, size: 18),
            label: Text(
              _uncRunning ? 'Checking...' : 'Run UNC Check',
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
        if (_uncResults != null) ...[
          const SizedBox(height: 16),
          Builder(builder: (context) {
            final passed = _uncResults!.where((r) => r.passed).length;
            final total = _uncResults!.length;
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
          ..._uncResults!.map((r) => Container(
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

const _sampleScript = '''
-- Try me! This runs in a real Luau VM, on-device.
local function fib(n)
    if n < 2 then return n end
    return fib(n - 1) + fib(n - 2)
end

for i = 1, 10 do
    print(`fib({i}) = {fib(i)}`)
end
''';

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
