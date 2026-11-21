import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/jarvis_service.dart';

enum ConversationRole { user, jarvis }

enum ConversationKind { normal, error, confirmation }

@immutable
class ConversationEntry {
  const ConversationEntry({
    required this.role,
    required this.text,
    required this.at,
    this.kind = ConversationKind.normal,
    this.acknowledged = true,
  });

  final ConversationRole role;
  final String text;
  final DateTime at;
  final ConversationKind kind;

  /// Errors and confirmations stay pinned on screen until acknowledged.
  final bool acknowledged;

  bool get needsAttention => kind != ConversationKind.normal && !acknowledged;

  ConversationEntry acknowledge() => ConversationEntry(
      role: role, text: text, at: at, kind: kind, acknowledged: true);

  Map<String, Object> toJson() => {
        'r': role.name,
        't': text,
        'at': at.millisecondsSinceEpoch,
        'k': kind.name,
        'a': acknowledged,
      };

  static ConversationEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! String || t.isEmpty) return null;
    return ConversationEntry(
      role: j['r'] == 'user' ? ConversationRole.user : ConversationRole.jarvis,
      text: t,
      at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
      kind: ConversationKind.values.firstWhere((k) => k.name == j['k'],
          orElse: () => ConversationKind.normal),
      // Anything restored from storage was already seen in a past session.
      acknowledged: true,
    );
  }
}

/// What the store reads from the JARVIS service on every change.
@immutable
class ConversationSignals {
  const ConversationSignals({
    required this.phase,
    required this.userText,
    required this.jarvisText,
    required this.status,
    this.awaitingConfirmation = false,
  });
  final JarvisPhase phase;
  final String userText;
  final String jarvisText;
  final String status;
  final bool awaitingConfirmation;
}

/// JARVIS-mode conversation history. Built from real service transitions:
/// a user turn is recorded when a request enters THINKING, a JARVIS turn when
/// a reply actually starts SPEAKING. Stored on the device only, and only when
/// "Save conversation" is on; turning it off keeps the session in memory.
class ConversationStore extends ChangeNotifier {
  ConversationStore({
    required Listenable source,
    required ConversationSignals Function() read,
    required bool Function() persist,
    this.maxEntries = 200,
  })  : _source = source,
        _read = read,
        _persist = persist {
    _last = _read();
    _source.addListener(_onChange);
  }

  static const storageKey = 'v3_jarvis_conversation';

  final Listenable _source;
  final ConversationSignals Function() _read;
  final bool Function() _persist;
  final int maxEntries;
  final List<ConversationEntry> _entries = [];
  late ConversationSignals _last;
  bool _disposed = false;

  List<ConversationEntry> get entries => List.unmodifiable(_entries);
  bool get hasPendingNotice => _entries.any((e) => e.needsAttention);

  /// The live partial transcript while the recogniser is capturing.
  String get liveTranscript =>
      _last.phase == JarvisPhase.listening ? _last.userText : '';

  Future<void> load() async {
    if (!_persist()) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(storageKey);
    if (raw == null || _disposed) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        final restored = list.map(ConversationEntry.fromJson).whereType<ConversationEntry>().toList();
        _entries.insertAll(0, restored);
        _trim();
        notifyListeners();
      }
    } catch (_) {
      // A damaged history is dropped rather than shown half-parsed.
      await p.remove(storageKey);
    }
  }

  void _onChange() {
    if (_disposed) return;
    final now = _read();
    final prev = _last;
    _last = now;
    var changed = false;

    if (now.phase == JarvisPhase.thinking && prev.phase != JarvisPhase.thinking &&
        now.userText.trim().isNotEmpty) {
      changed |= _add(ConversationEntry(
          role: ConversationRole.user, text: now.userText.trim(), at: DateTime.now()));
    }
    if (now.phase == JarvisPhase.speaking &&
        (prev.phase != JarvisPhase.speaking || prev.jarvisText != now.jarvisText) &&
        now.jarvisText.trim().isNotEmpty) {
      final isError = now.status.startsWith('AI ERROR');
      final kind = isError
          ? ConversationKind.error
          : now.awaitingConfirmation
              ? ConversationKind.confirmation
              : ConversationKind.normal;
      changed |= _add(ConversationEntry(
        role: ConversationRole.jarvis,
        text: now.jarvisText.trim(),
        at: DateTime.now(),
        kind: kind,
        acknowledged: kind == ConversationKind.normal,
      ));
    }
    if (now.phase == JarvisPhase.listening && prev.userText != now.userText) {
      changed = true; // live transcript updated
    }
    if (prev.phase != now.phase) changed = true;
    if (changed) notifyListeners();
  }

  bool _add(ConversationEntry e) {
    if (_entries.isNotEmpty) {
      final last = _entries.last;
      if (last.role == e.role && last.text == e.text &&
          e.at.difference(last.at).inSeconds.abs() < 5) {
        return false; // same turn reported twice
      }
    }
    _entries.add(e);
    _trim();
    _save();
    return true;
  }

  /// Records a turn that did not come through the phase machine (tests and
  /// the typed-input path when the service is unavailable).
  void addEntry(ConversationEntry e) {
    if (_add(e)) notifyListeners();
  }

  void acknowledgeAll() {
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].needsAttention) {
        _entries[i] = _entries[i].acknowledge();
        changed = true;
      }
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove(storageKey);
  }

  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  Future<void> _save() async {
    if (!_persist()) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(storageKey, jsonEncode([for (final e in _entries) e.toJson()]));
  }

  @override
  void dispose() {
    _disposed = true;
    _source.removeListener(_onChange);
    super.dispose();
  }
}
