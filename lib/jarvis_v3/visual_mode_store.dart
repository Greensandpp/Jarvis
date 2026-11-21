import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brain/visual_bus.dart';
import '../widgets/jarvis_visual_mode_host.dart';

/// The selected assistant model (JARVIS, AIRA, Office, APEX, MIRA, Serpent).
/// Shares the storage key of the previous host so the owner's choice carries
/// over to V3.
class VisualModeStore extends ValueNotifier<JarvisVisualMode> {
  VisualModeStore._() : super(JarvisVisualMode.core) {
    // Voice and brain commands ("switch to apex") arrive on the visual bus;
    // requestVisual() has already persisted them.
    visualBus.addListener(_onBus);
  }
  static final VisualModeStore instance = VisualModeStore._();

  void _onBus() {
    final m = visualBus.value?.mode;
    if (m == null) return;
    for (final v in JarvisVisualMode.values) {
      if (v.name == m) value = v;
    }
  }

  bool _loaded = false;

  /// Restores the saved mode once per process.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    value = JarvisVisualMode.values.firstWhere(
      (m) => m.name == p.getString(JarvisVisualModeHostState.storageKey),
      orElse: () => JarvisVisualMode.core,
    );
  }

  Future<void> select(JarvisVisualMode m) async {
    value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(JarvisVisualModeHostState.storageKey, m.name);
  }
}
