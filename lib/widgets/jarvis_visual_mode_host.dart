import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/task_executor.dart';
import 'jarvis_hud_widget.dart';

/// Visual preference only: phone actions remain in native JARVIS.
enum JarvisVisualMode { core, office, apex, mira }

class JarvisVisualModeHost extends StatefulWidget {
  const JarvisVisualModeHost({super.key, required this.onCommand, required this.onMicrophone});
  final ValueChanged<String> onCommand;
  final Future<void> Function() onMicrophone;
  @override
  State<JarvisVisualModeHost> createState() => _JarvisVisualModeHostState();
}

class _JarvisVisualModeHostState extends State<JarvisVisualModeHost> {
  static const storageKey = 'jarvis_visual_mode_v1';
  static const urls = {
    JarvisVisualMode.apex: 'https://apex-ui-xi.vercel.app/',
    JarvisVisualMode.mira: 'https://mira-hud.vercel.app/',
  };
  JarvisVisualMode mode = JarvisVisualMode.core;
  WebViewController? visual;
  final command = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final selected = JarvisVisualMode.values.firstWhere(
      (item) => item.name == prefs.getString(storageKey),
      orElse: () => JarvisVisualMode.core,
    );
    _select(selected, persist: false);
  }

  void _select(JarvisVisualMode next, {bool persist = true}) {
    WebViewController? controller;
    final url = urls[next];
    if (url != null) {
      final allowed = Uri.parse(url).host;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && uri.scheme == 'https' && uri.host == allowed
                ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Visual demo unavailable. Use JARVIS Core offline.'),
              ));
            }
          },
        ))
        ..loadRequest(Uri.parse(url));
    }
    setState(() { mode = next; visual = controller; });
    if (persist) {
      SharedPreferences.getInstance().then((p) => p.setString(storageKey, next.name));
    }
  }

  void _send() {
    final text = command.text.trim();
    if (text.isEmpty) return;
    command.clear();
    // Commands and secrets NEVER enter APEX/MIRA WebView.
    widget.onCommand(text);
  }

  @override
  void dispose() {
    command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00E5FF);
    return ColoredBox(color: Colors.black, child: Column(children: [
      SizedBox(height: 52, child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        children: [
          for (final item in JarvisVisualMode.values)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                selected: mode == item,
                label: Text(switch (item) {
                  JarvisVisualMode.core => 'JARVIS Core',
                  JarvisVisualMode.office => 'Agent Office',
                  JarvisVisualMode.apex => 'APEX',
                  JarvisVisualMode.mira => 'MIRA',
                }),
                onSelected: (_) => _select(item),
                selectedColor: const Color(0xFF064C55),
                backgroundColor: const Color(0xFF06161B),
                labelStyle: const TextStyle(color: Colors.white),
                side: BorderSide(color: mode == item ? cyan : const Color(0xFF27515A)),
              ),
            ),
        ],
      )),
      Expanded(child: switch (mode) {
        JarvisVisualMode.core => const JarvisHudWidget(),
        JarvisVisualMode.office => const _Office(),
        JarvisVisualMode.apex || JarvisVisualMode.mira => visual == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              Positioned.fill(child: WebViewWidget(controller: visual!)),
              const Positioned(right: 6, top: 5,
                child: Text('VISUAL DEMO · no private data shared',
                  style: TextStyle(color: Colors.white70, fontSize: 10))),
            ]),
      }),
      if (mode != JarvisVisualMode.core)
        Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: command, onSubmitted: (_) => _send(), maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '', hintText: 'Ask JARVIS privately',
                hintStyle: const TextStyle(color: Colors.white60), filled: true,
                fillColor: const Color(0xFF061A20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
              ),
            )),
            IconButton(tooltip: 'Speak to JARVIS',
              onPressed: () { widget.onMicrophone(); },
              icon: const Icon(Icons.mic, color: cyan)),
            IconButton(tooltip: 'Send to native JARVIS', onPressed: _send,
              icon: const Icon(Icons.send, color: cyan)),
          ])),
    ]));
  }
}

class _Office extends StatelessWidget {
  const _Office();
  @override
  Widget build(BuildContext context) {
    final executor = TaskExecutor.instance;
    return ListenableBuilder(listenable: executor, builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('JARVIS AGENT OFFICE', style: TextStyle(
          color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 7),
        const Text('Live native task state. Five AI specialists not connected yet.',
          style: TextStyle(color: Colors.white70)),
        Card(color: const Color(0xFF071B20), child: ListTile(
          title: Text(executor.currentGoal ?? 'No active task',
            style: const TextStyle(color: Colors.white)),
          subtitle: Text('Executor: ' + executor.state.name + ' · Step ' + executor.step.toString(),
            style: const TextStyle(color: Colors.white70)),
        )),
        for (final role in ['Chief', 'Developer', 'QA Tester', 'Security', 'Release Manager'])
          Card(color: const Color(0xFF07141A), child: ListTile(
            leading: const Icon(Icons.work_outline, color: Color(0xFF00E5FF)),
            title: Text(role, style: const TextStyle(color: Colors.white)),
            subtitle: const Text('NOT CONNECTED · no simulated progress',
              style: TextStyle(color: Colors.white60)),
          )),
      ],
    ));
  }
}
