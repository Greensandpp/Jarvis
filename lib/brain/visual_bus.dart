import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the brain / voice commands switch visual mode and AIRA model while the
/// visual host is on screen. Values are also persisted, so they survive restart.
class VisualRequest {
  final String? mode; // core / aira / office / apex / mira
  final String? airaModel; // AiraModel.name
  const VisualRequest({this.mode, this.airaModel});
}

final ValueNotifier<VisualRequest?> visualBus = ValueNotifier<VisualRequest?>(null);

const visualModes = ['core', 'aira', 'office', 'apex', 'mira'];

Future<void> requestVisual({String? mode, String? airaModel}) async {
  final p = await SharedPreferences.getInstance();
  if (mode != null) await p.setString('jarvis_visual_mode_v1', mode);
  if (airaModel != null) await p.setString('aira_model_v1', airaModel);
  visualBus.value = VisualRequest(mode: mode, airaModel: airaModel);
}
