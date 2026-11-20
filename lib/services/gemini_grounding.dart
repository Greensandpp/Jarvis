import 'dart:convert';
import 'package:http/http.dart' as http;
import '../brain/ai_reliability.dart';

class GroundedAnswer {
  const GroundedAnswer(this.text, this.sources, this.queries);
  final String text;
  final List<({String title, Uri url})> sources;
  final List<String> queries;

  String get markdown =>
      '$text\n\n${[for (var i = 0; i < sources.length; i++) '[${i + 1}] ${sources[i].title}: ${sources[i].url}'].join('\n')}';
}

/// Official Gemini generateContent API. API key is supplied at runtime, never
/// compiled into the app. Separate search call avoids model-specific conflicts
/// between custom functions and built-in grounding tools.
class GeminiGrounding {
  GeminiGrounding(this.client);
  final http.Client client;

  Future<GroundedAnswer> search({
    required String key,
    required String model,
    required String query,
    required bool cloudAllowed,
    required bool searchAllowed,
  }) async {
    if (!cloudAllowed || !searchAllowed) {
      throw const AiFailure(
        AiFailureKind.badRequest,
        detail: 'Enable cloud AI and external lookups in Settings first.',
      );
    }
    if (key.trim().isEmpty) throw const AiFailure(AiFailureKind.noKey);
    final id = model.replaceFirst('models/', '');
    if (!RegExp(r'^gemini-[a-zA-Z0-9._-]+$').hasMatch(id)) {
      throw const AiFailure(
        AiFailureKind.badRequest,
        detail: 'Select a Gemini text model that supports Google Search.',
      );
    }
    if (query.trim().isEmpty || query.length > 4000)
      throw const FormatException('Invalid search query');
    final response = await withRetry(() async {
      final r = await client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$id:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': query},
                  ],
                },
              ],
              'tools': [
                {'google_search': <String, dynamic>{}},
              ],
              'generationConfig': {'temperature': 0.1},
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) throw AiFailure.fromHttp(r.statusCode, r.body);
      return r;
    });
    return parse(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  static GroundedAnswer parse(Map<String, dynamic> body) {
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty)
      throw const FormatException('No grounded candidate');
    final c = candidates.first as Map;
    final parts = c['content']?['parts'] as List? ?? const [];
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'] ?? '')
        .join()
        .trim();
    final metadata = c['groundingMetadata'] as Map? ?? const {};
    final sources = <({String title, Uri url})>[];
    for (final chunk in metadata['groundingChunks'] as List? ?? const []) {
      final web = chunk is Map ? chunk['web'] : null;
      if (web is! Map) continue;
      final url = Uri.tryParse('${web['uri'] ?? ''}');
      if (url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty)
        continue;
      if (sources.any((s) => s.url == url)) continue;
      final title = '${web['title'] ?? url.host}'.replaceAll(
        RegExp(r'[\r\n\[\]]'),
        ' ',
      );
      sources.add((title: title, url: url));
    }
    if (text.isEmpty || sources.isEmpty) {
      throw const FormatException(
        'Gemini returned no verifiable grounding sources. Search not verified.',
      );
    }
    return GroundedAnswer(
      text,
      sources,
      (metadata['webSearchQueries'] as List? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}
