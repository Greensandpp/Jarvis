import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Why an AI request failed. DNS / TLS / connection problems are never
/// reported as model problems, and vice versa.
enum AiFailureKind {
  noKey,
  dns,
  tls,
  connect,
  timeout,
  badRequest,
  auth,
  modelNotFound,
  rateLimit,
  server,
  parse,
  cancelled,
}

class AiFailure implements Exception {
  const AiFailure(this.kind, {this.status, this.detail = ''});
  final AiFailureKind kind;
  final int? status;
  final String detail;

  bool get retryable =>
      kind == AiFailureKind.rateLimit ||
      kind == AiFailureKind.server ||
      kind == AiFailureKind.timeout;

  /// Plain-language message for the HUD, chat and diagnostics (key redacted).
  String get userMessage => switch (kind) {
    AiFailureKind.noKey =>
      'No AI key is set. Open Settings → AI provider and add your key.',
    AiFailureKind.dns =>
      'DNS failure: the phone could not look up the AI server. Check Wi-Fi/mobile data or Private DNS.',
    AiFailureKind.tls =>
      'Secure connection (TLS) to the AI server failed. Check the date/time, VPN or network filtering.',
    AiFailureKind.connect =>
      'Could not connect to the AI server (network unreachable or blocked).',
    AiFailureKind.timeout =>
      'The AI server did not respond in time. Please try again.',
    AiFailureKind.badRequest =>
      'The AI server rejected the request (HTTP ${status ?? 400}). $detail',
    AiFailureKind.auth =>
      'The AI provider rejected the API key (HTTP ${status ?? 401}). Check the key in Settings.',
    AiFailureKind.modelNotFound =>
      'Model not found (HTTP 404). Run "Test connection & discover models" and choose a listed model.',
    AiFailureKind.rateLimit =>
      'AI quota or rate limit reached (HTTP 429). Try again later.',
    AiFailureKind.server =>
      'The AI provider had a server error (HTTP ${status ?? 500}). Please try again shortly.',
    AiFailureKind.parse =>
      'The AI provider sent a response JARVIS could not read.',
    AiFailureKind.cancelled => 'Request cancelled.',
  };

  @override
  String toString() =>
      'AiFailure(${kind.name}${status == null ? '' : ', HTTP $status'})';

  /// Maps transport exceptions to a failure kind.
  static AiFailure fromException(Object e) {
    if (e is AiFailure) return e;
    if (e is TimeoutException) return const AiFailure(AiFailureKind.timeout);
    if (e is HandshakeException || e is TlsException)
      return const AiFailure(AiFailureKind.tls);
    if (e is SocketException) {
      final m =
          e.message.toLowerCase() + (e.osError?.message.toLowerCase() ?? '');
      if (m.contains('failed host lookup') ||
          m.contains('no address associated') ||
          m.contains('nodename nor servname')) {
        return const AiFailure(AiFailureKind.dns);
      }
      return const AiFailure(AiFailureKind.connect);
    }
    if (e is http.ClientException) {
      final m = e.message.toLowerCase();
      if (m.contains('failed host lookup'))
        return const AiFailure(AiFailureKind.dns);
      if (m.contains('handshake') || m.contains('certificate'))
        return const AiFailure(AiFailureKind.tls);
      return const AiFailure(AiFailureKind.connect);
    }
    if (e is FormatException) return const AiFailure(AiFailureKind.parse);
    return const AiFailure(AiFailureKind.connect);
  }

  /// Maps an HTTP error response. Google answers an invalid key with
  /// HTTP 400 API_KEY_INVALID, which is a key problem, not a bad request.
  static AiFailure fromHttp(int code, String body) {
    final msg = redact(_providerMessage(body));
    if (code == 400 &&
        (body.contains('API_KEY_INVALID') ||
            msg.toLowerCase().contains('api key not valid'))) {
      return AiFailure(AiFailureKind.auth, status: code, detail: msg);
    }
    return switch (code) {
      400 => AiFailure(AiFailureKind.badRequest, status: code, detail: msg),
      401 || 403 => AiFailure(AiFailureKind.auth, status: code, detail: msg),
      404 => AiFailure(AiFailureKind.modelNotFound, status: code, detail: msg),
      429 => AiFailure(AiFailureKind.rateLimit, status: code, detail: msg),
      >= 500 => AiFailure(AiFailureKind.server, status: code, detail: msg),
      _ => AiFailure(AiFailureKind.badRequest, status: code, detail: msg),
    };
  }

  static String _providerMessage(String body) {
    try {
      final j = jsonDecode(body);
      final err = j is List && j.isNotEmpty
          ? j.first['error']
          : (j is Map ? j['error'] : null);
      if (err is Map && err['message'] != null)
        return err['message'].toString();
      if (err is String) return err;
    } catch (_) {}
    return body.length > 160 ? '${body.substring(0, 160)}…' : body;
  }
}

/// Removes anything that looks like a key or token.
String redact(String s) => s
    .replaceAll(RegExp(r'AIza[0-9A-Za-z_\-]{10,}'), '[redacted-key]')
    .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_\-]{8,}'), '[redacted-key]')
    .replaceAllMapped(
      RegExp(r'(key|token)=([^&\s]+)', caseSensitive: false),
      (m) => '${m[1]}=[redacted]',
    );

typedef Sleeper = Future<void> Function(Duration d);

/// Runs [attempt] with exponential backoff on 429 / 5xx / timeouts.
Future<T> withRetry<T>(
  Future<T> Function() attempt, {
  int retries = 2,
  Sleeper? sleep,
  void Function(int n, AiFailure f)? onRetry,
}) async {
  final sl = sleep ?? (d) => Future<void>.delayed(d);
  for (var n = 0; ; n++) {
    try {
      return await attempt();
    } catch (e) {
      final f = AiFailure.fromException(e);
      if (!f.retryable || n >= retries) throw f;
      onRetry?.call(n + 1, f);
      await sl(
        Duration(
          milliseconds:
              (600 * math.pow(2, n)).round() + math.Random().nextInt(250),
        ),
      );
    }
  }
}

/// Lists chat-capable models from an OpenAI-compatible `GET {base}/models`
/// (works for Gemini's /v1beta/openai endpoint and most providers).
Future<List<String>> discoverModels(
  http.Client client,
  String base,
  String key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final ids = <String>[];
  String? pageToken;
  for (var page = 0; page < 5; page++) {
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/models')
        .replace(
          queryParameters: pageToken == null ? null : {'pageToken': pageToken},
        );
    final res = await client
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
        )
        .timeout(timeout);
    if (res.statusCode != 200)
      throw AiFailure.fromHttp(res.statusCode, res.body);
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final data =
        (j is Map ? (j['data'] ?? j['models']) : null) as List? ?? const [];
    for (final m in data) {
      if (m is Map &&
          m['supportedGenerationMethods'] is List &&
          !(m['supportedGenerationMethods'] as List).contains(
            'generateContent',
          ))
        continue;
      final id =
          (m is Map ? (m['id'] ?? m['name']) : m)?.toString().replaceFirst(
            'models/',
            '',
          ) ??
          '';
      final l = id.toLowerCase();
      if (id.isEmpty ||
          ['embedding', 'tts', 'image', 'audio', 'live', 'aqa'].any(l.contains))
        continue;
      if (!ids.contains(id)) ids.add(id);
    }
    final next = j is Map ? j['nextPageToken']?.toString() : null;
    if (next == null || next.isEmpty || next == pageToken) break;
    pageToken = next;
  }
  return ids;
}

/// Preferred model first, then discovered "flash" models (newest-looking first), then others.
List<String> fallbackOrder(String preferred, List<String> discovered) {
  final out = <String>[];
  if (preferred.isNotEmpty) out.add(preferred);
  final flash = discovered.where((m) => m.contains('flash')).toList()
    ..sort((a, b) => b.compareTo(a));
  final other = discovered.where((m) => !m.contains('flash')).toList()
    ..sort((a, b) => b.compareTo(a));
  for (final m in [...flash, ...other]) {
    if (!out.contains(m)) out.add(m);
  }
  return out;
}

/// A bounded, generation-only retry loop. Android tools execute after this
/// returns, never inside the transport retry. A listed model is not verified
/// until a non-empty completion or a tool call is received.
Future<({String model, Map<String, dynamic> message})> completeWithFallback({
  required String preferred,
  required List<String> cached,
  required Future<List<String>> Function() discover,
  required Future<http.Response> Function(String model) send,
  Sleeper? sleep,
  bool allowDiscovery = true,
}) async {
  var models = cached;
  var discovered = false;
  Future<void> refresh() async {
    if (discovered || !allowDiscovery) return;
    discovered = true;
    try {
      models = await discover();
    } on AiFailure catch (f) {
      if (f.kind == AiFailureKind.auth) rethrow;
    } catch (_) {
      /* A cached model may still work when listing is unavailable. */
    }
  }

  if (models.isEmpty) await refresh();
  var current = preferred;
  final tried = <String>{};
  AiFailure? last;
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      final r = await send(current);
      if (r.statusCode != 200) throw AiFailure.fromHttp(r.statusCode, r.body);
      final message = completionMessage(r);
      return (model: current, message: message);
    } catch (e) {
      last = AiFailure.fromException(e);
      // Never retry auth, malformed requests, TLS, DNS, or ambiguous timeouts.
      if (last.kind != AiFailureKind.modelNotFound &&
          last.kind != AiFailureKind.rateLimit &&
          last.kind != AiFailureKind.server)
        rethrow;
      tried.add(current);
      await refresh();
      final remaining = fallbackOrder(
        '',
        models,
      ).where((m) => !tried.contains(m));
      if (last.kind == AiFailureKind.modelNotFound && remaining.isEmpty)
        throw last;
      if (attempt == 3) break;
      if (last.retryable) {
        await (sleep ?? (d) => Future<void>.delayed(d))(
          Duration(milliseconds: 600 * (1 << attempt)),
        );
      }
      if (remaining.isNotEmpty) current = remaining.first;
    }
  }
  throw last ?? const AiFailure(AiFailureKind.modelNotFound);
}

Map<String, dynamic> completionMessage(http.Response response) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final message = decoded['choices'][0]['message'];
    if (message is! Map) throw const FormatException('Missing message');
    final content = message['content'];
    final text = content is String
        ? content
        : content is List
        ? content.map((p) => p is Map ? '${p['text'] ?? ''}' : '$p').join()
        : '';
    final calls = message['tool_calls'];
    if (text.trim().isEmpty && (calls is! List || calls.isEmpty)) {
      throw const FormatException('Empty completion');
    }
    return {
      'role': 'assistant',
      'content': text,
      if (calls is List && calls.isNotEmpty) 'tool_calls': calls,
    };
  } catch (_) {
    throw const AiFailure(AiFailureKind.parse);
  }
}

enum StepStatus { pass, fail, skipped }

class DiagStep {
  const DiagStep(this.name, this.status, this.detail, this.ms);
  final String name;
  final StepStatus status;
  final String detail;
  final int ms;
  @override
  String toString() =>
      '${status.name.toUpperCase()}  $name (${ms}ms) — $detail';
}

class DiagReport {
  final steps = <DiagStep>[];
  var models = <String>[];
  var online = false;
  var workingModel = '';
  String summary() =>
      '${online ? 'ONLINE via $workingModel' : 'NOT ONLINE'}\n${steps.join('\n')}';
}

typedef Resolver = Future<List<InternetAddress>> Function(String host);

/// DNS → HTTPS/TLS → key + model discovery → real generation. ONLINE only if
/// a real chat completion succeeds.
Future<DiagReport> runDiagnostics({
  required http.Client client,
  required String base,
  required String key,
  required String model,
  Resolver? resolve,
}) async {
  final rep = DiagReport();
  final b = base.replaceAll(RegExp(r'/+$'), '');
  final host = Uri.parse(b).host;
  var sw = Stopwatch()..start();
  void skipRest(String why, List<String> names) {
    for (final n in names) {
      rep.steps.add(DiagStep(n, StepStatus.skipped, 'skipped: $why', 0));
    }
  }

  try {
    final addrs = await (resolve ?? InternetAddress.lookup)(
      host,
    ).timeout(const Duration(seconds: 10));
    rep.steps.add(
      DiagStep(
        'DNS $host',
        StepStatus.pass,
        '${addrs.length} address(es)',
        sw.elapsedMilliseconds,
      ),
    );
  } catch (_) {
    rep.steps.add(
      DiagStep(
        'DNS $host',
        StepStatus.fail,
        'cannot resolve host — check internet / Private DNS',
        sw.elapsedMilliseconds,
      ),
    );
    skipRest('DNS failed', [
      'HTTPS handshake',
      'API key + model discovery',
      'Generate',
    ]);
    return rep;
  }
  sw = Stopwatch()..start();
  try {
    final r = await client
        .get(Uri.parse('$b/models'))
        .timeout(const Duration(seconds: 15));
    rep.steps.add(
      DiagStep(
        'HTTPS handshake',
        StepStatus.pass,
        'TLS ok, HTTP ${r.statusCode} without key',
        sw.elapsedMilliseconds,
      ),
    );
  } catch (e) {
    final f = AiFailure.fromException(e);
    rep.steps.add(
      DiagStep(
        'HTTPS handshake',
        StepStatus.fail,
        f.userMessage,
        sw.elapsedMilliseconds,
      ),
    );
    skipRest(f.kind.name, ['API key + model discovery', 'Generate']);
    return rep;
  }
  if (key.isEmpty) {
    rep.steps.add(
      const DiagStep(
        'API key + model discovery',
        StepStatus.fail,
        'No API key set.',
        0,
      ),
    );
    skipRest('no key', ['Generate']);
    return rep;
  }
  sw = Stopwatch()..start();
  try {
    rep.models = await discoverModels(client, b, key);
    rep.steps.add(
      DiagStep(
        'API key + model discovery',
        StepStatus.pass,
        '${rep.models.length} chat models',
        sw.elapsedMilliseconds,
      ),
    );
  } catch (e) {
    final f = AiFailure.fromException(e);
    rep.steps.add(
      DiagStep(
        'API key + model discovery',
        StepStatus.fail,
        f.userMessage,
        sw.elapsedMilliseconds,
      ),
    );
    if (f.kind == AiFailureKind.auth) {
      skipRest('key problem', ['Generate']);
      return rep;
    }
  }
  sw = Stopwatch()..start();
  try {
    final result = await completeWithFallback(
      preferred: model,
      cached: rep.models,
      discover: () async => rep.models,
      allowDiscovery: false,
      send: (m) => client
          .post(
            Uri.parse('$b/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': m,
              'max_tokens': 32,
              'messages': [
                {'role': 'user', 'content': 'Reply with OK.'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30)),
    );
    rep.workingModel = result.model;
    rep.online = true;
    rep.steps.add(
      DiagStep(
        'Generate with ${result.model}',
        StepStatus.pass,
        '${result.model == model ? '' : 'preferred unavailable, fell back. '}reply received',
        sw.elapsedMilliseconds,
      ),
    );
  } catch (e) {
    rep.steps.add(
      DiagStep(
        'Generate with $model',
        StepStatus.fail,
        AiFailure.fromException(e).userMessage,
        sw.elapsedMilliseconds,
      ),
    );
  }
  return rep;
}
