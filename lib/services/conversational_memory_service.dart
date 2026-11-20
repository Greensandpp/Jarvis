import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hermes_evolution_service.dart';
import '../brain/memory_backup.dart';

/// A remembered fact or user preference that persists across sessions.
class MemoryFact {
  final String id;
  final String fact;
  final String category; // 'preference', 'personal', 'work', 'habit'
  final DateTime createdAt;
  /// Earlier versions of this fact, oldest first (kept when the owner corrects it).
  final List<String> history;

  const MemoryFact({
    required this.id,
    required this.fact,
    this.category = 'personal',
    required this.createdAt,
    this.history = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fact': fact,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        if (history.isNotEmpty) 'history': history,
      };

  factory MemoryFact.fromJson(Map<String, dynamic> json) => MemoryFact(
        id: json['id'] as String? ?? UniqueKey().toString(),
        fact: json['fact'] as String? ?? '',
        category: json['category'] as String? ?? 'personal',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        history: (json['history'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

/// Persistent memory service:
/// 1. Remembers short-term conversation context across app restarts.
/// 2. Remembers long-term user facts, preferences, and habits.
/// 3. Injects user memory into AI system prompts.
/// 4. Provides full privacy controls (view, delete individually, wipe all).
class ConversationalMemoryService extends ChangeNotifier {
  ConversationalMemoryService._();
  static final ConversationalMemoryService instance =
      ConversationalMemoryService._();

  static const _factsKey = 'jarvis_memory_facts_v1';
  static const _historyKey = 'jarvis_memory_history_v1';
  static const _maxHistoryMessages = 20;

  final List<MemoryFact> _facts = [];
  final List<Map<String, String>> _persistedHistory = [];
  bool _initialized = false;

  List<MemoryFact> get facts => List.unmodifiable(_facts);
  List<Map<String, String>> get persistedHistory =>
      List.unmodifiable(_persistedHistory);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();

    // 1. Load long-term facts
    final factsRaw = prefs.getString(_factsKey);
    if (factsRaw != null && factsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(factsRaw);
        if (decoded is List) {
          _facts.clear();
          for (final item in decoded) {
            if (item is Map) {
              _facts.add(
                MemoryFact.fromJson(item.map((k, v) => MapEntry('$k', v))),
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Load short-term history across sessions
    final historyRaw = prefs.getString(_historyKey);
    if (historyRaw != null && historyRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(historyRaw);
        if (decoded is List) {
          _persistedHistory.clear();
          for (final item in decoded) {
            if (item is Map) {
              _persistedHistory.add({
                'role': item['role']?.toString() ?? 'user',
                'content': item['content']?.toString() ?? '',
              });
            }
          }
        }
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> _persistFacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _factsKey,
      jsonEncode(_facts.map((f) => f.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_persistedHistory),
    );
  }

  /// Adds a short-term message pair to cross-session memory.
  Future<void> recordTurn(String userText, String assistantText) async {
    await init();
    _persistedHistory.add({'role': 'user', 'content': userText.trim()});
    _persistedHistory.add({'role': 'assistant', 'content': assistantText.trim()});
    if (_persistedHistory.length > _maxHistoryMessages) {
      _persistedHistory.removeRange(
        0,
        _persistedHistory.length - _maxHistoryMessages,
      );
    }
    await _persistHistory();

    // Check if user explicitly asked to remember something
    await extractAndSaveImplicitFacts(userText);
  }

  /// Extracts "Remember that...", "My favorite ... is ...", etc.
  Future<void> extractAndSaveImplicitFacts(String text) async {
    final lower = text.toLowerCase().trim();
    String? fact;
    String category = 'personal';

    if (lower.startsWith('remember that ') || lower.startsWith('remember ')) {
      fact = text.replaceFirst(RegExp(r'remember\s+(that\s+)?', caseSensitive: false), '').trim();
    } else if (lower.startsWith('note that ') || lower.startsWith('keep in mind that ')) {
      fact = text.replaceFirst(RegExp(r'(note|keep in mind)\s+that\s+', caseSensitive: false), '').trim();
    } else if (lower.contains('my favorite ') && lower.contains(' is ')) {
      fact = text.trim();
      category = 'preference';
    } else if (lower.contains('my name is ') || lower.contains('i live in ') || lower.contains('my email is ')) {
      fact = text.trim();
      category = 'personal';
    }

    if (fact != null && fact.isNotEmpty && fact.length >= 3) {
      await addFact(fact, category: category);
    }
  }

  /// Saves a persistent fact into long-term memory.
  Future<MemoryFact> addFact(String fact, {String category = 'personal'}) async {
    await init();
    final clean = fact.trim();
    // Avoid exact duplicates
    final existingIndex = _facts.indexWhere(
      (f) => f.fact.toLowerCase() == clean.toLowerCase(),
    );
    if (existingIndex >= 0) {
      return _facts[existingIndex];
    }

    final newFact = MemoryFact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fact: clean,
      category: category,
      createdAt: DateTime.now(),
    );
    _facts.insert(0, newFact);
    await _persistFacts();
    try {
      HermesEvolutionService.instance.evolveContext().catchError((_) {});
    } catch (_) {}
    return newFact;
  }

  /// Corrects a fact in place. The previous wording is kept in [MemoryFact.history]
  /// so a correction can be reviewed or undone.
  Future<MemoryFact?> correctFact(String id, String corrected) async {
    await init();
    final i = _facts.indexWhere((f) => f.id == id);
    final clean = corrected.trim();
    if (i < 0 || clean.isEmpty) return null;
    final old = _facts[i];
    if (old.fact == clean) return old;
    final updated = MemoryFact(id: old.id, fact: clean, category: old.category,
        createdAt: DateTime.now(), history: [...old.history, old.fact]);
    _facts[i] = updated;
    await _persistFacts();
    notifyListeners();
    _refreshLearnedContext();
    return updated;
  }

  /// Re-synthesises the Hermes learned context so corrections reach the AI prompt.
  void _refreshLearnedContext() {
    try {
      HermesEvolutionService.instance.evolveContext().catchError((_) {});
    } catch (_) {}
  }

  /// Undo the last correction of a fact.
  Future<MemoryFact?> undoCorrection(String id) async {
    await init();
    final i = _facts.indexWhere((f) => f.id == id);
    if (i < 0 || _facts[i].history.isEmpty) return null;
    final f = _facts[i];
    _facts[i] = MemoryFact(id: f.id, fact: f.history.last, category: f.category,
        createdAt: f.createdAt, history: f.history.sublist(0, f.history.length - 1));
    await _persistFacts();
    notifyListeners();
    _refreshLearnedContext();
    return _facts[i];
  }

  /// Facts most relevant to [query] (for prompt injection / recall).
  List<MemoryFact> relevantFacts(String query, {int limit = 8}) {
    final scored = [for (final f in _facts) (f, relevance(query, f.fact, f.createdAt))]
      ..removeWhere((e) => e.$2 < 0.2)
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }

  /// Passphrase-encrypted export of long-term facts (see memory_backup.dart).
  Future<String> exportEncrypted(String passphrase, {int iterations = 60000}) async {
    await init();
    return encryptBackup(jsonEncode(_facts.map((f) => f.toJson()).toList()), passphrase, iterations: iterations);
  }

  /// Verifies and merges an encrypted backup. Returns how many new facts were
  /// added. Throws [BackupException] (and changes nothing) on a wrong
  /// passphrase or tampered file.
  Future<int> importEncrypted(String backup, String passphrase) async {
    await init();
    final list = jsonDecode(decryptBackup(backup, passphrase));
    if (list is! List) throw const BackupException('Backup content is not a fact list.');
    var added = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final f = MemoryFact.fromJson(item.map((k, v) => MapEntry('$k', v)));
      if (f.fact.isEmpty || _facts.any((e) => e.fact.toLowerCase() == f.fact.toLowerCase())) continue;
      _facts.add(f);
      added++;
    }
    if (added > 0) {
      await _persistFacts();
      notifyListeners();
      _refreshLearnedContext();
    }
    return added;
  }

  /// Removes an individual fact from memory.
  Future<void> deleteFact(String id) async {
    await init();
    _facts.removeWhere((f) => f.id == id);
    await _persistFacts();
    try {
      HermesEvolutionService.instance.evolveContext().catchError((_) {});
    } catch (_) {}
  }

  /// Privacy: Clears all stored long-term facts.
  Future<void> clearAllFacts() async {
    await init();
    _facts.clear();
    await _persistFacts();
  }

  /// Privacy: Clears conversation session history.
  Future<void> clearAllHistory() async {
    await init();
    _persistedHistory.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    notifyListeners();
  }

  /// Privacy: Complete wipe of all conversational memory.
  Future<void> wipeAll() async {
    await clearAllFacts();
    await clearAllHistory();
  }

  /// Builds context string of remembered facts to inject into AI system prompt.
  String buildMemoryContext() {
    if (_facts.isEmpty) return '';
    final buffer = StringBuffer('USER MEMORY & PREFERENCES:\n');
    for (final f in _facts.take(12)) {
      buffer.writeln('- ${f.fact}');
    }
    return buffer.toString().trim();
  }
}

