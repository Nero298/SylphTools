import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/luau_runner_service.dart';
import '../models/sylph_instance_node.dart';
import '../widgets/sylph_gui_preview.dart';

class ScriptRunnerScreen extends StatefulWidget {
  const ScriptRunnerScreen({super.key});

  @override
  State<ScriptRunnerScreen> createState() => _ScriptRunnerScreenState();
}

class _ScriptRunnerScreenState extends State<ScriptRunnerScreen>
    with SingleTickerProviderStateMixin {
  final _luau = Get.find<LuauRunnerService>();
  final _codeCtrl = TextEditingController(text: _sampleScript);
  late final TabController _resultTabController;

  bool _running = false;
  LuauRunResult? _result;
  List<SylphInstanceNode> _guiTree = const [];

  // The session handle for the currently-running script. Kept alive across
  // runs of the SAME script (so GUI event callbacks stay valid) but
  // recreated whenever the user hits Run again, since a fresh run should
  // start from a clean VM rather than accumulating leftover globals/state
  // from the previous run.
  int? _sessionHandle;

  @override
  void initState() {
    super.initState();
    _resultTabController = TabController(length: 2, vsync: this);
    _resultTabController.addListener(() {
      // Rebuilds so the Copy button (Output-tab-only) shows/hides
      // correctly even when the user swipes between tabs instead of
      // tapping them.
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _resultTabController.dispose();
    if (_sessionHandle != null) {
      _luau.disposeSession(_sessionHandle!);
    }
    super.dispose();
  }

  Future<void> _runScript() async {
    final source = _codeCtrl.text;

    // Tear down any previous session first — each tap of Run starts a
    // fresh VM, so leftover globals/instances/callbacks from an earlier
    // run never leak into the new one.
    if (_sessionHandle != null) {
      _luau.disposeSession(_sessionHandle!);
      _sessionHandle = null;
    }

    setState(() {
      _running = true;
      _result = null;
      _guiTree = const [];
    });

    // Native calls are synchronous C++ under the hood; hop off the UI
    // thread briefly so a heavy script doesn't visibly freeze the frame.
    final handle = await Future(() => _luau.createSession());
    if (handle == null) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = LuauRunResult(
          success: false,
          output: _luau.loadError ?? 'Failed to start Luau runtime.',
        );
      });
      return;
    }

    final result = await Future(() => _luau.runInSession(handle, source));
    final treeJson = result.success ? await Future(() => _luau.snapshot(handle)) : '[]';

    if (!mounted) {
      // Screen was closed mid-run — clean up rather than leak the session.
      _luau.disposeSession(handle);
      return;
    }

    setState(() {
      _running = false;
      _result = result;
      _sessionHandle = handle;
      _guiTree = SylphInstanceNode.parseForest(treeJson);
    });
    if (_guiTree.isNotEmpty) {
      _resultTabController.animateTo(1); // jump to Preview automatically
    }
  }

  /// Called by [SylphGuiPreview] when the user taps something in the
  /// preview (currently just TextButton). Invokes the corresponding
  /// `:Connect()`-ed Luau callback, then re-snapshots the tree since the
  /// callback may have changed properties (e.g. updated a label's Text).
  Future<void> _onFireEvent(int instanceId, String eventName) async {
    final handle = _sessionHandle;
    if (handle == null) return;

    final fireResult = await Future(() => _luau.fireEvent(handle, instanceId, eventName));
    final treeJson = await Future(() => _luau.snapshot(handle));

    if (!mounted) return;
    setState(() {
      _guiTree = SylphInstanceNode.parseForest(treeJson);
      if (!fireResult.success) {
        // Surface event-handler errors the same way script errors are
        // shown, and flip back to the Output tab so the user notices.
        _result = fireResult;
        _resultTabController.animateTo(0);
      }
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
                            'Real Luau VM, on-device — with a mock GUI API (Instance.new, '
                            'game/workspace, UDim2/Color3) so scripts that build a ScreenGui '
                            'render a live preview. There\'s no real game/workspace data, so '
                            'game-specific logic outside GUI code will still error.',
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
                    _buildResultSection(context),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(BuildContext context) {
    final hasPreview = _guiTree.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _resultTabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.accentHi,
                unselectedLabelColor: context.textM,
                indicatorColor: AppColors.accentHi,
                labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _result!.success ? Icons.check_circle_rounded : Icons.error_rounded,
                          size: 14,
                          color: _result!.success ? AppColors.green : AppColors.red,
                        ),
                        const SizedBox(width: 6),
                        Text(_result!.success ? 'Output' : 'Error'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smartphone_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(hasPreview ? 'Preview' : 'Preview (empty)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_resultTabController.index == 0)
              TextButton.icon(
                onPressed: _copyOutput,
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text('Copy', style: GoogleFonts.inter(fontSize: 12.5)),
                style: TextButton.styleFrom(foregroundColor: AppColors.accentHi),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 420,
          child: TabBarView(
            controller: _resultTabController,
            children: [
              _buildOutputTab(context),
              _buildPreviewTab(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOutputTab(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _result!.success ? context.bgHover : AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: _result!.success ? null : Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _result!.output.isEmpty ? '(no output)' : _result!.output,
          style: GoogleFonts.robotoMono(fontSize: 12, color: context.text, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildPreviewTab(BuildContext context) {
    if (_guiTree.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: context.bgHover,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          'No GUI created by this script.\nTry Instance.new("ScreenGui") parented\nto game.Players.LocalPlayer.PlayerGui.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12.5, color: context.textD, height: 1.5),
        ),
      );
    }

    // A plain black canvas roughly standing in for the Roblox game screen —
    // GUI elements are typically designed against a dark background, and
    // this also makes it visually obvious this is a "device screen"
    // preview rather than part of the app's own chrome.
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Colors.black,
        child: SylphGuiPreview(
          roots: _guiTree,
          onFireEvent: _onFireEvent,
        ),
      ),
    );
  }
}

const _sampleScript = '''
-- Try me! Builds a small interactive GUI you can preview live.
local gui = Instance.new("ScreenGui")
gui.Parent = game.Players.LocalPlayer.PlayerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 140)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 40)
label.Position = UDim2.new(0, 0, 0, 10)
label.Text = "Clicks: 0"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 18
label.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 160, 0, 44)
button.Position = UDim2.new(0, 30, 0, 70)
button.Text = "Click me"
button.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = button

local clicks = 0
button.MouseButton1Click:Connect(function()
    clicks = clicks + 1
    label.Text = "Clicks: " .. clicks
end)

print("GUI built — check the Preview tab, then tap the button.")
''';
