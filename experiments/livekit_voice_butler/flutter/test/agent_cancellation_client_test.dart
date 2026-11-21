import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/agent_cancellation_client.dart';

void main() {
  const room = 'roomA';
  const reply = 'responseB';
  const generation = 17;

  AgentCancellationClient make(http.Client client, {Uri? uri}) =>
      AgentCancellationClient(
        endpoint: uri ?? Uri.parse('https://voice.example.invalid/cancel'),
        client: client,
        authorizationToken: () async => 'test-only-token',
        timeout: const Duration(milliseconds: 40),
      );

  http.Response acknowledged() => http.Response(
        jsonEncode({
          'cancelled': true,
          'room_id': room,
          'response_id': reply,
          'generation': generation,
        }),
        200,
      );

  test('requires HTTPS before creating transport', () {
    expect(
      () => make(MockClient((_) async => acknowledged()),
          uri: Uri.parse('http://localhost/cancel')),
      throwsArgumentError,
    );
  });

  test('accepts exact authenticated backend cancellation acknowledgement',
      () async {
    final client = make(MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer test-only-token');
      expect(request.headers['content-type'], 'application/json');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['room_id'], room);
      expect(body['response_id'], reply);
      expect(body['generation'], generation);
      return acknowledged();
    }));
    expect(
        await client.cancel(
            roomId: room, generation: generation, responseId: reply),
        true);
  });

  test('rejects matching HTTP success without an explicit ack', () async {
    final client = make(MockClient((_) async => http.Response('{}', 200)));
    expect(
        await client.cancel(
            roomId: room, generation: generation, responseId: reply),
        false);
  });

  test('rejects mismatched generation acknowledgement', () async {
    final client = make(MockClient((_) async => http.Response(
        jsonEncode({
          'cancelled': true,
          'room_id': room,
          'response_id': reply,
          'generation': generation - 1
        }),
        200)));
    expect(
        await client.cancel(
            roomId: room, generation: generation, responseId: reply),
        false);
  });

  test('rejects unauthorized, malformed and failing responses', () async {
    for (final response in [
      http.Response('forbidden', 403),
      http.Response('nope', 200),
      http.Response('internal', 500),
    ]) {
      final client = make(MockClient((_) async => response));
      expect(
          await client.cancel(
              roomId: room, generation: generation, responseId: reply),
          false);
    }
  });

  test('rejects cancellation timeout rather than assuming stop', () async {
    final never = Completer<http.Response>();
    final client = make(MockClient((_) => never.future));
    expect(
        await client.cancel(
            roomId: room, generation: generation, responseId: reply),
        false);
  });

  test('rejects invalid request before network call', () async {
    var calls = 0;
    final client = make(MockClient((_) async {
      calls++;
      return acknowledged();
    }));
    expect(
        await client.cancel(roomId: '', generation: 1, responseId: reply),
        false);
    expect(calls, 0);
  });
}
