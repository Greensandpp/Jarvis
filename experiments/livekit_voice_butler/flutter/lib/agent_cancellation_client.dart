import 'dart:convert';

import 'package:http/http.dart' as http;

/// Own-backend cancellation protocol; NOT a built-in LiveKit endpoint.
/// Server must authenticate the caller, authorize room/turn membership, cancel
/// response generation and confirm audio generation will not continue.
///
/// A server response with only HTTP 200 but no explicit acknowledgment fails.
class AgentCancellationClient {
  AgentCancellationClient({
    required this.endpoint,
    required this.authorizationToken,
    required this.client,
    this.timeout = const Duration(seconds: 3),
  }) {
    if (endpoint.scheme != 'https') {
      throw ArgumentError('Cancellation endpoint must use HTTPS.');
    }
  }

  final Uri endpoint;
  final Future<String> Function() authorizationToken;
  final http.Client client;
  final Duration timeout;

  Future<bool> cancel({
    required String roomId,
    required int generation,
    required String responseId,
  }) async {
    if (roomId.trim().isEmpty || generation < 0 || responseId.trim().isEmpty) {
      return false;
    }
    try {
      final token = await authorizationToken().timeout(timeout);
      if (token.trim().isEmpty) return false;
      final result = await client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
            },
            body: jsonEncode({
              'room_id': roomId,
              'generation': generation,
              'response_id': responseId,
            }),
          )
          .timeout(timeout);
      if (result.statusCode != 200) return false;
      final parsed = jsonDecode(result.body);
      return parsed is Map<String, dynamic> &&
          parsed['cancelled'] == true &&
          parsed['room_id'] == roomId &&
          parsed['response_id'] == responseId &&
          parsed['generation'] == generation;
    } catch (_) {
      // Any network, auth, timeout, malformed JSON or schema error fails closed.
      return false;
    }
  }
}
