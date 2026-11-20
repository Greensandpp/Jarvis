import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import '../services/conversational_memory_service.dart';
import '../services/settings_service.dart';
import 'memory_backup.dart' show relevance;

typedef Embedder = Future<List<List<double>>> Function(List<String> texts);

/// Memory recall: semantic (embeddings) when online and allowed, keyword
/// relevance otherwise. Embeddings are cached per fact text on the phone.
class SemanticMemory {
  SemanticMemory({Embedder? embedder, this.enabled}) : _embedder = embedder;
  static final SemanticMemory instance = SemanticMemory();

  final Embedder? _embedder;
  final bool Function()? enabled;
  static const _cacheKey = 'jarvis_memory_embeddings_v1';
  Map<String, List<double>>? _cache;
  String lastMode = 'keyword';

  bool get _on => enabled?.call() ??
      (SettingsService.instance.semanticMemory && SettingsService.instance.provider == 'gemini' &&
          AiService.instance.aiBlockedReason == null);

  Embedder get _embed => _embedder ?? (t) => AiService.instance.embedTexts(t);

  static String _h(String s) => sha1.convert(utf8.encode(s.toLowerCase().trim())).toString().substring(0, 16);

  static double cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Future<Map<String, List<double>>> _load() async {
    if (_cache != null) return _cache!;
    final p = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(p.getString(_cacheKey) ?? '{}') as Map<String, dynamic>;
      _cache = j.map((k, v) => MapEntry(k, [for (final x in v as List) (x as num).toDouble()]));
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cacheKey, jsonEncode(_cache));
  }

  List<MemoryFact> keyword(String query, List<MemoryFact> facts, int limit) {
    final scored = [for (final f in facts) (f, relevance(query, f.fact, f.createdAt))]
      ..removeWhere((e) => e.$2 < 0.2)
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }

  Future<List<MemoryFact>> recall(String query, List<MemoryFact> facts, {int limit = 6, double minScore = 0.55}) async {
    if (facts.isEmpty || query.trim().isEmpty) return const [];
    if (!_on) {
      lastMode = 'keyword';
      return keyword(query, facts, limit);
    }
    try {
      final cache = await _load();
      final missing = facts.where((f) => !cache.containsKey(_h(f.fact))).toList();
      if (missing.isNotEmpty) {
        final vecs = await _embed(missing.map((f) => f.fact).toList());
        for (var i = 0; i < missing.length && i < vecs.length; i++) {
          cache[_h(missing[i].fact)] = vecs[i];
        }
        await _save();
      }
      final q = (await _embed([query])).first;
      final scored = [
        for (final f in facts)
          if (cache[_h(f.fact)] != null) (f, cosine(q, cache[_h(f.fact)]!) + 0.3 * relevance(query, f.fact, f.createdAt)),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      lastMode = 'semantic';
      final hits = [for (final e in scored.where((e) => e.$2 >= minScore).take(limit)) e.$1];
      // Keep exact keyword hits even if the embedding score is low.
      for (final k in keyword(query, facts, limit)) {
        if (!hits.contains(k) && hits.length < limit) hits.add(k);
      }
      return hits;
    } catch (_) {
      lastMode = 'keyword (embedding failed)';
      return keyword(query, facts, limit);
    }
  }
}
