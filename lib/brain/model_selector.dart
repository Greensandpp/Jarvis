import 'dart:math' as math;

import 'ai_reliability.dart';

/// Parsed Gemini model id, e.g. `gemini-2.5-flash`, `gemini-3.5-flash-lite`,
/// `gemini-2.5-pro-preview-06-05`, `gemini-flash-latest`.
class GeminiModelInfo {
  const GeminiModelInfo(this.id, {required this.version, required this.tier, required this.preview});
  final String id;
  final double version; // 0 when unknown (e.g. *-latest aliases)
  final String tier; // flash, flash-lite, pro, other
  final bool preview; // preview / exp / experimental / thinking builds

  static GeminiModelInfo? parse(String raw) {
    final id = raw.replaceFirst('models/', '').trim();
    final l = id.toLowerCase();
    if (!l.startsWith('gemini')) return null;
    final v = RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(l);
    final version = v == null ? 0.0 : double.tryParse(v.group(1)!) ?? 0.0;
    final tier = l.contains('flash-lite') || l.contains('flash-8b')
        ? 'flash-lite'
        : l.contains('flash')
            ? 'flash'
            : l.contains('pro')
                ? 'pro'
                : 'other';
    final preview = RegExp(r'preview|exp|thinking|-\d{2}-\d{2}$').hasMatch(l);
    return GeminiModelInfo(id, version: version, tier: tier, preview: preview);
  }
}

/// Orders models for automatic selection and fallback.
///
/// Gemini (preferred provider): stable before preview; within that, Flash
/// (best speed/quality for a voice assistant) → Flash-Lite (highest free
/// quota, used as the 429 fallback) → Pro → others; newest version first.
/// Other providers keep the existing `fallbackOrder` behaviour.
List<String> rankModels(List<String> ids, {String provider = 'gemini'}) {
  final unique = <String>[];
  for (final raw in ids) {
    final id = raw.replaceFirst('models/', '').trim();
    if (id.isNotEmpty && !unique.contains(id)) unique.add(id);
  }
  if (provider != 'gemini') return fallbackOrder('', unique);
  const tierOrder = {'flash': 0, 'flash-lite': 1, 'pro': 2, 'other': 3};
  final parsed = <GeminiModelInfo>[];
  final rest = <String>[];
  for (final id in unique) {
    final p = GeminiModelInfo.parse(id);
    if (p == null) {
      rest.add(id);
    } else {
      parsed.add(p);
    }
  }
  parsed.sort((a, b) {
    if (a.preview != b.preview) return a.preview ? 1 : -1;
    final t = tierOrder[a.tier]!.compareTo(tierOrder[b.tier]!);
    if (t != 0) return t;
    final v = b.version.compareTo(a.version);
    if (v != 0) return v;
    return a.id.compareTo(b.id);
  });
  return [...parsed.map((p) => p.id), ...rest..sort()];
}

/// Best model to auto-select, or null when nothing usable was discovered.
String? pickBestModel(List<String> discovered, {String provider = 'gemini'}) {
  final r = rankModels(discovered, provider: provider);
  return r.isEmpty ? null : r.first;
}

/// Per-model cool-down after rate limits / overload so the next requests do
/// not hammer a model that just returned 429 or 503.
class ModelCooldowns {
  final Map<String, DateTime> _until = {};
  final Map<String, String> _why = {};

  bool cooling(String model, DateTime now) {
    final u = _until[model];
    return u != null && now.isBefore(u);
  }

  void mark(String model, Duration d, DateTime now, String why) {
    _until[model] = now.add(d);
    _why[model] = why;
  }

  String? reason(String model) => _why[model];
  void clear() {
    _until.clear();
    _why.clear();
  }

  Map<String, DateTime> get snapshot => Map.unmodifiable(_until);
}

/// Outcome of one model attempt (for logs, diagnostics and tests).
class ModelAttempt {
  const ModelAttempt(this.model, this.outcome);
  final String model;
  final String outcome; // ok / 429 / 5xx / timeout / 404 / skipped-cooldown
  @override
  String toString() => '$model:$outcome';
}

class FallbackResult<T> {
  const FallbackResult(this.value, this.model, this.attempts, {required this.selectedUnavailable});
  final T value;
  final String model; // the model that answered
  final List<ModelAttempt> attempts;
  /// True when the selected model answered 404 (gone for this key), so the
  /// caller should persist [model] as the new selection.
  final bool selectedUnavailable;
}

/// Calls [attempt] with the selected model, then falls back through [ranked]
/// on HTTP 429 (quota/rate limit), 5xx/503 (overload) and timeouts.
///
/// Bounded: at most [maxAttempts] HTTP requests in total, at most
/// [retriesPer5xx] same-model retry after a 5xx/timeout, and no new attempt
/// after [deadline]. Auth / DNS / TLS / connect / parse failures are not
/// model-specific and are rethrown immediately (no pointless retries).
///
/// Only the chat request is repeated — never a tool/Android action — so a
/// fallback cannot run an action twice.
Future<FallbackResult<T>> callWithModelFallback<T>({
  required String selected,
  required List<String> ranked,
  required Future<T> Function(String model) attempt,
  ModelCooldowns? cooldowns,
  int maxAttempts = 4,
  int retriesPer5xx = 1,
  Duration deadline = const Duration(seconds: 75),
  Sleeper? sleep,
  DateTime Function()? clock,
  void Function(ModelAttempt a)? onAttempt,
}) async {
  final now = clock ?? DateTime.now;
  final sl = sleep ?? (d) => Future<void>.delayed(d);
  final cd = cooldowns ?? ModelCooldowns();
  final start = now();
  final attempts = <ModelAttempt>[];
  void log(ModelAttempt a) {
    attempts.add(a);
    onAttempt?.call(a);
  }

  // Candidate order: selected first (unless cooling down and others exist).
  final order = <String>[];
  if (selected.isNotEmpty) order.add(selected);
  for (final m in ranked) {
    if (!order.contains(m)) order.add(m);
  }
  final fresh = order.where((m) => !cd.cooling(m, now())).toList();
  for (final m in order) {
    if (cd.cooling(m, now()) && fresh.isNotEmpty) log(ModelAttempt(m, 'skipped-cooldown'));
  }
  final candidates = fresh.isNotEmpty ? fresh : order;

  var requests = 0;
  // A selected model skipped because it recently answered 404 is gone too.
  var selectedGone = !candidates.contains(selected) && (cd.reason(selected)?.contains('404') ?? false);
  AiFailure? last;
  for (final m in candidates) {
    var retries = 0;
    var again = true;
    while (again) {
      again = false;
      if (requests >= maxAttempts || now().difference(start) >= deadline) {
        throw last ?? const AiFailure(AiFailureKind.timeout);
      }
      requests++;
      try {
        final v = await attempt(m);
        log(ModelAttempt(m, 'ok'));
        return FallbackResult(v, m, attempts, selectedUnavailable: selectedGone && m != selected);
      } catch (e) {
        final f = AiFailure.fromException(e);
        last = f;
        if (f.kind == AiFailureKind.rateLimit) {
          log(ModelAttempt(m, '429'));
          cd.mark(m, const Duration(seconds: 60), now(), 'rate limit (HTTP 429)');
        } else if (f.kind == AiFailureKind.server || f.kind == AiFailureKind.timeout) {
          log(ModelAttempt(m, f.kind == AiFailureKind.timeout ? 'timeout' : '${f.status ?? 503}'));
          if (retries < retriesPer5xx) {
            retries++;
            await sl(Duration(milliseconds: 500 * (1 << (retries - 1)) + math.Random().nextInt(200)));
            again = true;
          } else {
            cd.mark(m, const Duration(seconds: 30), now(), 'overloaded (HTTP ${f.status ?? 503})');
          }
        } else if (f.kind == AiFailureKind.modelNotFound) {
          log(ModelAttempt(m, '404'));
          if (m == selected) selectedGone = true;
          cd.mark(m, const Duration(hours: 6), now(), 'not available for this key (HTTP 404)');
        } else {
          throw f; // key, network, TLS, parse: not model-specific
        }
      }
    }
  }
  throw last ?? const AiFailure(AiFailureKind.server);
}
