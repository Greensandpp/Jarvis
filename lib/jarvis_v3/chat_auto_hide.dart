import 'dart:async';

import 'package:flutter/foundation.dart';

import 'assistant_activity.dart';

/// Reasons the conversation must stay on screen regardless of the timer.
enum ChatHold {
  scrolling,
  inputFocus,
  keyboard,
  historyOpen,
  pendingNotice, // unread error/confirmation or a permission/security prompt
}

/// Smart auto-hide for the conversation layer.
///
/// The conversation is visible while the assistant is genuinely active
/// (listening, thinking, processing, executing, speaking when enabled) or
/// while any [ChatHold] is held. Only when all of those end does the
/// inactivity countdown start; when it elapses the bubbles fade out. History
/// is never deleted.
class ChatAutoHideController extends ChangeNotifier {
  ChatAutoHideController({
    required bool enabled,
    required Duration delay,
    bool showWhileSpeaking = true,
  })  : _enabled = enabled,
        _delay = delay,
        _showWhileSpeaking = showWhileSpeaking;

  bool _enabled;
  Duration _delay;
  bool _showWhileSpeaking;
  AssistantActivity _activity = AssistantActivity.idle;
  final Set<ChatHold> _holds = {};
  bool _visible = true;
  Timer? _timer;
  bool _disposed = false;

  bool get visible => _visible;
  bool get enabled => _enabled;
  Duration get delay => _delay;
  Set<ChatHold> get holds => Set.unmodifiable(_holds);

  /// True while a countdown to hiding is running.
  bool get countingDown => _timer?.isActive ?? false;

  bool get _pinned {
    if (_holds.isNotEmpty) return true;
    if (_activity == AssistantActivity.speaking) return _showWhileSpeaking;
    return _activity.isActiveConversation;
  }

  void configure({bool? enabled, Duration? delay, bool? showWhileSpeaking}) {
    if (enabled != null) _enabled = enabled;
    if (delay != null) _delay = delay;
    if (showWhileSpeaking != null) _showWhileSpeaking = showWhileSpeaking;
    _evaluate(restart: true);
  }

  void setActivity(AssistantActivity a) {
    if (a == _activity) return;
    final wasPinned = _pinned;
    _activity = a;
    // Any genuine activity reveals the conversation.
    if (_pinned) _show();
    _evaluate(restart: wasPinned != _pinned);
  }

  void hold(ChatHold h) {
    if (_holds.add(h)) {
      _show();
      _evaluate();
    }
  }

  void release(ChatHold h) {
    if (_holds.remove(h)) _evaluate(restart: true);
  }

  /// A tap on the conversation area, a new message, or opening the panel.
  void reveal() {
    _show();
    _evaluate(restart: true);
  }

  void _show() {
    if (!_visible) {
      _visible = true;
      _notify();
    }
  }

  void _evaluate({bool restart = false}) {
    if (_disposed) return;
    if (!_enabled) {
      _timer?.cancel();
      _show();
      return;
    }
    if (_pinned) {
      _timer?.cancel();
      return;
    }
    if (!_visible) return;
    if (restart || !(_timer?.isActive ?? false)) {
      _timer?.cancel();
      _timer = Timer(_delay, () {
        if (_disposed || _pinned || !_enabled) return;
        _visible = false;
        _notify();
      });
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
