import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// A WebView screen with SylphTools' own top bar wrapped around a real,
/// visible web page. We deliberately show the actual site rather than
/// trying to hide/scrape it — sites like Perchance render their UI via
/// client-side JS with dynamic class names, so faking a native UI on top
/// would break silently whenever the site updates. Showing the real page
/// (with light CSS theming) is far more reliable.
class AppWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  /// Optional CSS injected into the page once it finishes loading, to
  /// nudge its colors closer to SylphTools' palette. Best-effort only —
  /// if the site's CSS structure changes, this may stop matching and the
  /// page will just render with its own styling, which is safe.
  final String? injectedCss;

  const AppWebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.injectedCss,
  });

  @override
  State<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends State<AppWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.darkBg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _loading = true;
            _failed = false;
          }),
          onPageFinished: (_) async {
            if (widget.injectedCss != null) {
              await _injectCss(widget.injectedCss!);
            }
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Only treat main-frame failures as fatal; ignore errors from
            // sub-resources (ads, analytics, etc.) that don't affect usability.
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _failed = true;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _injectCss(String css) async {
    final escaped = css.replaceAll('`', r'\`').replaceAll('\n', ' ');
    try {
      await _controller.runJavaScript('''
        (function() {
          try {
            var style = document.createElement('style');
            style.id = 'sylphtools-theme-inject';
            style.innerHTML = `$escaped`;
            document.head.appendChild(style);
          } catch (e) {}
        })();
      ''');
    } catch (_) {
      // Injection failing is non-fatal — page still works with its own styling.
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: context.textM, size: 21),
                    onPressed: () => _controller.reload(),
                    tooltip: 'Reload',
                  ),
                  IconButton(
                    icon: Icon(Icons.open_in_new_rounded, color: context.textM, size: 19),
                    onPressed: _openExternally,
                    tooltip: 'Open in browser',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    Container(
                      color: context.bg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.accentHi,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Loading ${widget.title}...',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: context.textM,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_failed)
                    Container(
                      color: context.bg,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 40,
                                color: context.textD,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Couldn\'t load ${widget.title}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Check your connection, or open it in your browser instead.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: context.textM,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _controller.reload(),
                                    child: const Text('Retry'),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: _openExternally,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Open in Browser'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
