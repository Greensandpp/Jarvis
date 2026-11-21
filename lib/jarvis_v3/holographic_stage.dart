import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'assistant_activity.dart';
import 'chat_interface_settings.dart';

/// Local, silent WebGL scene. Its bridge can report status or request a mic tap;
/// it cannot execute scripts, navigate, read files or invoke Android actions.
class HolographicStage extends StatefulWidget {
  const HolographicStage({
    super.key,
    required this.activity,
    required this.theme,
    required this.soundLevel,
    required this.onTap,
    required this.onIntroFinished,
    required this.playIntro,
    required this.reduceMotion,
    this.onReady,
  });
  final ValueListenable<AssistantActivity> activity;
  final String theme;
  final double Function() soundLevel;
  final VoidCallback onTap, onIntroFinished;
  final VoidCallback? onReady;
  final bool playIntro, reduceMotion;
  @override
  State<HolographicStage> createState() => HolographicStageState();
}

class HolographicStageState extends State<HolographicStage>
    with WidgetsBindingObserver {
  WebViewController? _web;
  bool _ready = false;
  bool get renderingReady => _ready;
  String? get rendererError => _error;
  Future<Map<String, dynamic>> snapshot() async {
    final raw = await _web?.runJavaScriptReturningResult(
      'JSON.stringify(window.jarvisScene?.snapshot())',
    );
    if (raw == null) return {};
    dynamic decoded = jsonDecode(raw.toString());
    if (decoded is String) decoded = jsonDecode(decoded);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.activity.addListener(_sync);
    if (Platform.isAndroid) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final code = await rootBundle.loadString(
        'assets/hologram/scene.bundle.js',
      );
      if (!mounted) return;
      final web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF01070B))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (r) => r.url == 'about:blank'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
          ),
        )
        ..addJavaScriptChannel(
          'HologramBridge',
          onMessageReceived: (m) {
            if (!mounted || m.message.length > 2048) return;
            try {
              final v = jsonDecode(m.message) as Map;
              switch (v['type']) {
                case 'ready':
                  final firstReady = !_ready;
                  _ready = true;
                  _sync();
                  if (firstReady) widget.onReady?.call();
                case 'tap':
                  widget.onTap();
                case 'introFinished':
                  widget.onIntroFinished();
                case 'metrics':
                  if (kDebugMode)
                    debugPrint('HOLOGRAM_RENDERER_METRICS ${m.message}');
                case 'error':
                  setState(() => _error = '${v['message']}');
              }
            } catch (_) {
              /* Ignore malformed/unrecognised messages. */
            }
          },
        );
      _web = web;
      await web.loadHtmlString('''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; media-src 'none'">
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#01070b}canvas{display:block;touch-action:none}</style>
</head><body><script>$code</script></body></html>''');
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '3D renderer could not start');
    }
  }

  Future<void> _sync() async {
    if (!_ready || !mounted) return;
    final payload = jsonEncode({
      'state': widget.activity.value.name,
      'quality': ChatInterfaceSettings.instance.quality,
      'theme': widget.theme,
      'level': widget.soundLevel(),
      'intro': widget.playIntro,
      'reduceMotion': widget.reduceMotion,
    });
    try {
      await _web?.runJavaScript('window.jarvisScene?.update($payload)');
    } catch (_) {}
  }

  void skipIntro() {
    unawaited(
      _web?.runJavaScript('window.jarvisScene?.skipIntro()') ?? Future.value(),
    );
  }

  @override
  void didUpdateWidget(covariant HolographicStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.removeListener(_sync);
      widget.activity.addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    unawaited(
      _web?.runJavaScript('window.jarvisScene?.pause($paused)') ??
          Future.value(),
    );
  }

  @override
  void dispose() {
    widget.activity.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _web?.runJavaScript('window.jarvisScene?.pause(true)') ?? Future.value(),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null)
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.amber)),
      );
    if (_web == null)
      return const Center(
        child: Text(
          '3D renderer requires Android WebView',
          style: TextStyle(color: Colors.white54),
        ),
      );
    return WebViewWidget(controller: _web!);
  }
}
