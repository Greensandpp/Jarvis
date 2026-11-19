import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/services/agent_office/agent_office.dart';

Map<String, dynamic> _live() => {
      'mode': 'live',
      'runId': 'run-42',
      'mission': {'title': 'Android 16 QA'},
      'agents': [
        {'id': 'chief', 'state': 'working', 'task': 'Plan', 'message': 'ok'},
        {'id': 'qa', 'state': 'rejected', 'task': 'Emulator', 'message': 'install failed'},
        {'id': 'hacker', 'state': 'working'},
        {'id': 'developer', 'state': 'flying'},
      ],
      'events': [
        {'agent': 'qa', 'state': 'rejected', 'message': 'token AIzaSyD-THIS_IS_NOT_A_REAL_KEY_123456 leaked',
          'evidence': 'run 99', 'time': '2026-11-19T10:00:00Z'},
      ],
      'handoffs': [
        {'from': 'chief', 'to': 'developer', 'goal': 'g', 'work': 'w', 'evidence': 'e',
          'status': 's', 'blockers': 'none', 'next': 'n'},
        {'from': 'developer', 'to': 'qa', 'goal': 'missing fields'},
      ],
      'approvals': [
        {'action': 'deploy staging', 'status': 'executed', 'approvedByOwner': false},
        {'action': 'search docs', 'status': 'executed'},
      ],
      'board': {'rejects': 1},
    };

void main() {
  test('bundled handoff sample JSON is never shown as live', () {
    final sample = jsonDecode(File('test/fixtures/team-status.sample.json').readAsStringSync());
    final snap = OfficeSnapshot.parse(sample as Map<String, dynamic>, authenticated: true);
    expect(snap.source, OfficeSource.sample);
    expect(snap.isLive, isFalse);
  });

  test('live requires BOTH authentication and mode=live', () {
    expect(OfficeSnapshot.parse(_live(), authenticated: false).source, OfficeSource.sample);
    final snap = OfficeSnapshot.parse(_live(), authenticated: true);
    expect(snap.source, OfficeSource.authenticated);
    // Unknown roles and invalid states are dropped, not invented.
    expect(snap.agents.keys, unorderedEquals([AgentRole.chief, AgentRole.qa]));
    expect(snap.agents[AgentRole.qa]!.state, AgentState.rejected);
  });

  test('provider text is sanitized and secrets are redacted', () {
    final snap = OfficeSnapshot.parse(_live(), authenticated: true);
    expect(snap.events.single.message, isNot(contains('AIza')));
    expect(snap.events.single.message, contains('[redacted]'));
    expect(sanitizeOfficeText('otp: 482913 then pay'), isNot(contains('482913')));
    expect(sanitizeOfficeText('x' * 1000).length, lessThan(310));
  });

  test('handoffs need Goal/Work/Evidence/Status/Blockers/Next', () {
    final snap = OfficeSnapshot.parse(_live(), authenticated: true);
    expect(snap.handoffs, hasLength(1));
    expect(snap.handoffs.single.to, AgentRole.developer);
  });

  test('RED action executed without owner approval is flagged', () {
    final snap = OfficeSnapshot.parse(_live(), authenticated: true);
    expect(snap.policyViolations.single, contains('deploy staging'));
  });

  test('permission tiers', () {
    expect(PermissionTier.classify('search the web'), PermissionTier.green);
    expect(PermissionTier.classify('draft reply'), PermissionTier.green);
    expect(PermissionTier.classify('edit file in work folder'), PermissionTier.yellow);
    for (final a in ['send WhatsApp', 'purchase item', 'delete repo', 'deploy release',
        'grant permission', 'recharge mobile', 'place order']) {
      expect(PermissionTier.classify(a), PermissionTier.red, reason: a);
      expect(OfficeWorkflow.needsOwnerApproval(a), isTrue);
    }
  });

  test('workflow: independent rejection with evidence, max 3 loops then owner', () {
    final w = OfficeWorkflow();
    expect(w.advance(), AgentRole.developer);
    expect(w.advance(), AgentRole.qa);
    expect(() => w.reject(by: AgentRole.developer, evidence: 'x'), throwsArgumentError);
    expect(() => w.reject(by: AgentRole.qa, evidence: ' '), throwsArgumentError);
    expect(w.reject(by: AgentRole.qa, evidence: 'test failed'), AgentRole.developer);
    expect(w.reject(by: AgentRole.security, evidence: 'leak'), AgentRole.developer);
    expect(w.reject(by: AgentRole.qa, evidence: 'still failing'), isNull);
    expect(w.escalated, isTrue);
    expect(w.advance(), isNull);
    expect(w.audit.last, contains('Escalated to owner'));
  });

  test('release is never advanced automatically', () {
    final w = OfficeWorkflow()..stage = AgentRole.security;
    expect(w.advance(), isNull);
    expect(w.audit.last, contains('owner approval'));
  });

  group('authenticated provider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('unconfigured is DISCONNECTED, never sample or live', () async {
      final c = AgentOfficeController(client: MockClient((_) async => http.Response('{}', 200)));
      await c.refresh();
      expect(c.snapshot.source, OfficeSource.disconnected);
    });

    test('rejects non-HTTPS endpoints and short tokens', () async {
      final c = AgentOfficeController();
      expect(await c.configure('http://example.com/status', 'x' * 20), contains('HTTPS'));
      expect(await c.configure('https://user:pw@example.com', 'x' * 20), isNotNull);
      expect(await c.configure('https://example.com/status', 'short'), isNotNull);
    });

    test('sends bearer token and parses live data', () async {
      String? auth;
      final c = AgentOfficeController(client: MockClient((req) async {
        auth = req.headers['Authorization'];
        return http.Response(jsonEncode(_live()), 200);
      }));
      expect(await c.configure('https://office.example/status', 'tok_0123456789abcdef'), isNull);
      await c.refresh();
      expect(auth, 'Bearer tok_0123456789abcdef');
      expect(c.snapshot.isLive, isTrue);
    });

    test('401 and network errors become DISCONNECTED with no raw error text', () async {
      final c = AgentOfficeController(client: MockClient((_) async => http.Response('nope', 401)));
      await c.configure('https://office.example/status', 'tok_0123456789abcdef');
      await c.refresh();
      expect(c.snapshot.source, OfficeSource.disconnected);
      expect(c.snapshot.error, 'Provider rejected credentials');

      final d = AgentOfficeController(client: MockClient((_) async =>
          throw const SocketException('secret-host.internal:443 token=abc')));
      await d.refresh();
      expect(d.snapshot.error, 'Provider unreachable');
    });
  });
}
