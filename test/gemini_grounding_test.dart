import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:private_agent/services/gemini_grounding.dart';
import 'package:private_agent/brain/ai_reliability.dart';

Map<String, dynamic> grounded() => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': 'தமிழ் mixed answer.'},
        ],
      },
      'groundingMetadata': {
        'groundingChunks': [
          {
            'web': {
              'uri': 'https://example.org/source',
              'title': 'Primary source',
            },
          },
          {
            'web': {'uri': 'javascript:alert(1)', 'title': 'unsafe'},
          },
          {
            'web': {
              'uri': 'https://user:secret@example.org/',
              'title': 'unsafe',
            },
          },
        ],
        'webSearchQueries': ['Tamil question'],
      },
    },
  ],
};
void main() {
  test(
    'TEST DOUBLE: official Gemini request returns real metadata citations',
    () async {
      var calls = 0;
      final api = GeminiGrounding(
        MockClient((r) async {
          calls++;
          expect(r.url.host, 'generativelanguage.googleapis.com');
          expect(r.url.path, endsWith(':generateContent'));
          expect(r.url.queryParameters, isEmpty);
          expect(r.headers['x-goog-api-key'], 'runtime-only');
          final body = jsonDecode(r.body);
          expect(body['tools'].single.containsKey('google_search'), isTrue);
          expect(r.body, contains('தமிழ்'));
          return http.Response(
            jsonEncode(grounded()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final r = await api.search(
        key: 'runtime-only',
        model: 'gemini-test',
        query: 'தமிழ்',
        cloudAllowed: true,
        searchAllowed: true,
      );
      expect(calls, 1);
      expect(r.sources.length, 1);
      expect(r.markdown, contains('https://example.org/source'));
    },
  );
  test(
    'privacy denies all network requests before key or query can leave',
    () async {
      var calls = 0;
      final api = GeminiGrounding(
        MockClient((r) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.search(
          key: 'runtime-only',
          model: 'gemini-test',
          query: 'private',
          cloudAllowed: true,
          searchAllowed: false,
        ),
        throwsA(isA<AiFailure>()),
      );
      expect(calls, 0);
    },
  );
  test('text with no grounding metadata is never presented as grounded', () {
    expect(
      () => GeminiGrounding.parse({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'made up'},
              ],
            },
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
