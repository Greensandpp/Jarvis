import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Five-agent office: data model, honesty rules and an authenticated,
/// read-only status provider. Nothing here executes agent work; it only
/// displays state that a trusted backend reports, and never fabricates it.

enum AgentRole {
  chief('Chief', 'Plans and delegates'),
  developer('Developer', 'Implements scoped tasks'),
  qa('QA Tester', 'Independent verification'),
  security('Security', 'Independent security review'),
  release('Release Manager', 'Owner-gated release');

  const AgentRole(this.label, this.duty);
  final String label;
  final String duty;

  static AgentRole? parse(Object? v) {
    final s = '$v'.toLowerCase().trim();
    for (final r in AgentRole.values) {
      if (r.name == s) return r;
    }
    return switch (s) {
      'qa_tester' || 'qa-tester' || 'tester' => AgentRole.qa,
      'release_manager' || 'release-manager' => AgentRole.release,
      _ => null,
    };
  }
}

enum AgentState {
  idle, working, handoff, rejected, waiting, done;

  static AgentState? parse(Object? v) {
    final s = '$v'.toLowerCase().trim();
    for (final st in AgentState.values) {
      if (st.name == s) return st;
    }
    return null;
  }
}

/// Green = read/search/draft. Yellow = create/edit inside the designated work
/// folder. Red = send/post/purchase/delete/permissions/new accounts/deploy and
/// always requires explicit owner approval.
enum PermissionTier {
  green, yellow, red;

  static PermissionTier classify(String action) {
    final a = action.toLowerCase();
    const red = [
      'send', 'post', 'publish', 'purchase', 'pay', 'buy', 'recharge', 'delete',
      'remove', 'permission', 'grant', 'account', 'login', 'deploy', 'release',
      'merge', 'order', 'transfer', 'install',
    ];
    const yellow = ['create', 'edit', 'write', 'modify', 'update', 'commit', 'rename'];
    if (red.any(a.contains)) return PermissionTier.red;
    if (yellow.any(a.contains)) return PermissionTier.yellow;
    return PermissionTier.green;
  }
}

enum OfficeSource { disconnected, sample, authenticated }

final _control = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
final _secretPatterns = <RegExp>[
  RegExp(r'AIza[0-9A-Za-z_\-]{20,}'),
  RegExp(r'\bsk-[A-Za-z0-9_\-]{16,}'),
  RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}'),
  RegExp(r'Bearer\s+[A-Za-z0-9._\-]{12,}', caseSensitive: false),
  RegExp(r'\b(?:otp|pin|password|passcode)\s*[:=]?\s*\S+', caseSensitive: false),
  RegExp(r'\b\d{12,19}\b'), // card / account-like numbers
];

/// Sanitises text from the provider before display: strips control chars,
/// redacts secret-looking values and caps length.
String sanitizeOfficeText(Object? raw, {int max = 300}) {
  var s = (raw ?? '').toString().replaceAll(_control, ' ').trim();
  for (final p in _secretPatterns) {
    s = s.replaceAll(p, '[redacted]');
  }
  return s.length > max ? '${s.substring(0, max)}…' : s;
}

class AgentStatus {
  const AgentStatus(this.role, this.state, this.task, this.message);
  final AgentRole role;
  final AgentState state;
  final String task;
  final String message;
}

class OfficeEvent {
  const OfficeEvent({required this.agent, required this.state, required this.message,
      this.time, this.evidence = ''});
  final AgentRole agent;
  final AgentState state;
  final String message;
  final DateTime? time;
  final String evidence;
}

/// Every handoff must carry Goal / Work / Evidence / Status / Blockers / Next.
class Handoff {
  const Handoff({required this.from, required this.to, required this.goal,
      required this.work, required this.evidence, required this.status,
      required this.blockers, required this.next});
  final AgentRole from, to;
  final String goal, work, evidence, status, blockers, next;

  static const requiredFields = ['goal', 'work', 'evidence', 'status', 'blockers', 'next'];

  static Handoff? parse(Map<String, dynamic> j) {
    final from = AgentRole.parse(j['from']), to = AgentRole.parse(j['to']);
    if (from == null || to == null) return null;
    for (final k in requiredFields) {
      if (!j.containsKey(k)) return null; // incomplete handoffs are rejected
    }
    String f(String k) => sanitizeOfficeText(j[k]);
    return Handoff(from: from, to: to, goal: f('goal'), work: f('work'),
        evidence: f('evidence'), status: f('status'), blockers: f('blockers'),
        next: f('next'));
  }
}

class ApprovalRecord {
  const ApprovalRecord({required this.action, required this.tier,
      required this.status, this.approvedByOwner = false});
  final String action;
  final PermissionTier tier;
  final String status; // pending | approved | denied | executed
  final bool approvedByOwner;
}

class OfficeSnapshot {
  OfficeSnapshot({
    required this.source,
    this.runId = '',
    this.mission = '',
    Map<AgentRole, AgentStatus>? agents,
    this.events = const [],
    this.handoffs = const [],
    this.approvals = const [],
    this.blockers = const [],
    this.qaResults = const [],
    this.rejections = 0,
    this.fetchedAt,
    this.error,
  }) : agents = agents ?? {};

  final OfficeSource source;
  final String runId;
  final String mission;
  final Map<AgentRole, AgentStatus> agents;
  final List<OfficeEvent> events;
  final List<Handoff> handoffs;
  final List<ApprovalRecord> approvals;
  final List<String> blockers;
  final List<String> qaResults;
  final int rejections;
  final DateTime? fetchedAt;
  final String? error;

  bool get isLive => source == OfficeSource.authenticated;

  static OfficeSnapshot disconnected([String? why]) =>
      OfficeSnapshot(source: OfficeSource.disconnected, error: why);

  /// Policy violations the UI must surface instead of hiding.
  List<String> get policyViolations {
    final out = <String>[];
    for (final a in approvals) {
      if (a.tier == PermissionTier.red &&
          (a.status == 'executed' || a.status == 'approved') &&
          !a.approvedByOwner) {
        out.add('RED action "${a.action}" reported ${a.status} without owner approval');
      }
    }
    if (rejections > OfficeWorkflow.maxRejections) {
      out.add('Rejection loop exceeded ${OfficeWorkflow.maxRejections}; must escalate to owner');
    }
    return out;
  }

  /// Parses a provider document. A document is only treated as live when the
  /// request was authenticated AND the document declares mode "live". Anything
  /// else (including the bundled example with mode "sample") is labelled SAMPLE.
  static OfficeSnapshot parse(Map<String, dynamic> j, {required bool authenticated}) {
    final mode = '${j['mode']}'.toLowerCase();
    final source = authenticated && mode == 'live'
        ? OfficeSource.authenticated
        : OfficeSource.sample;
    final agents = <AgentRole, AgentStatus>{};
    for (final a in (j['agents'] as List? ?? const [])) {
      if (a is! Map) continue;
      final role = AgentRole.parse(a['id']);
      final state = AgentState.parse(a['state']);
      if (role == null || state == null) continue;
      agents[role] = AgentStatus(role, state, sanitizeOfficeText(a['task'], max: 160),
          sanitizeOfficeText(a['message'], max: 200));
    }
    final events = <OfficeEvent>[];
    for (final e in (j['events'] as List? ?? const []).take(100)) {
      if (e is! Map) continue;
      final role = AgentRole.parse(e['agent']);
      final state = AgentState.parse(e['state']);
      if (role == null || state == null) continue;
      events.add(OfficeEvent(agent: role, state: state,
          message: sanitizeOfficeText(e['message']),
          evidence: sanitizeOfficeText(e['evidence']),
          time: DateTime.tryParse('${e['time']}')));
    }
    final handoffs = <Handoff>[];
    for (final h in (j['handoffs'] as List? ?? const []).take(50)) {
      if (h is Map<String, dynamic>) {
        final p = Handoff.parse(h);
        if (p != null) handoffs.add(p);
      }
    }
    final approvals = <ApprovalRecord>[];
    for (final a in (j['approvals'] as List? ?? const []).take(50)) {
      if (a is! Map) continue;
      final action = sanitizeOfficeText(a['action'], max: 120);
      approvals.add(ApprovalRecord(
        action: action,
        tier: PermissionTier.classify(action),
        status: sanitizeOfficeText(a['status'], max: 20).toLowerCase(),
        approvedByOwner: a['approvedByOwner'] == true,
      ));
    }
    final board = j['board'] is Map ? j['board'] as Map : const {};
    return OfficeSnapshot(
      source: source,
      runId: sanitizeOfficeText(j['runId'], max: 64),
      mission: sanitizeOfficeText((j['mission'] is Map ? j['mission']['title'] : j['mission']), max: 120),
      agents: agents,
      events: events,
      handoffs: handoffs,
      approvals: approvals,
      blockers: [for (final b in (j['blockers'] as List? ?? const []).take(20)) sanitizeOfficeText(b)],
      qaResults: [for (final q in (j['qaResults'] as List? ?? const []).take(20)) sanitizeOfficeText(q)],
      rejections: (board['rejects'] is int) ? board['rejects'] as int : 0,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Routing policy for the specialist pipeline. Used to validate reported
/// state and by any future orchestrator; it never runs agents by itself.
class OfficeWorkflow {
  static const maxRejections = 3;
  static const pipeline = [
    AgentRole.chief, AgentRole.developer, AgentRole.qa, AgentRole.security, AgentRole.release,
  ];

  int rejections = 0;
  AgentRole stage = AgentRole.chief;
  bool escalated = false;
  final List<String> audit = [];

  /// Advance to the next stage. Release is never automatic.
  AgentRole? advance() {
    if (escalated) return null;
    final i = pipeline.indexOf(stage);
    if (i + 1 >= pipeline.length) return null;
    final next = pipeline[i + 1];
    if (next == AgentRole.release) {
      audit.add('Release requires owner approval');
      return null;
    }
    stage = next;
    audit.add('handoff → ${next.label}');
    return next;
  }

  /// QA or Security rejects with evidence; work routes back to [returnTo]
  /// (owner-assigned, default Developer). After 3 rejections, escalate.
  AgentRole? reject({required AgentRole by, required String evidence,
      AgentRole returnTo = AgentRole.developer}) {
    if (by != AgentRole.qa && by != AgentRole.security) {
      throw ArgumentError('Only QA Tester or Security may reject');
    }
    if (evidence.trim().isEmpty) throw ArgumentError('Rejection requires evidence');
    rejections++;
    audit.add('${by.label} rejected: ${sanitizeOfficeText(evidence, max: 120)}');
    if (rejections >= maxRejections) {
      escalated = true;
      audit.add('Escalated to owner after $rejections rejections');
      return null;
    }
    stage = returnTo;
    return returnTo;
  }

  static bool needsOwnerApproval(String action) =>
      PermissionTier.classify(action) == PermissionTier.red;
}

/// Read-only authenticated provider. HTTPS only; bearer token supplied by the
/// owner and stored locally. No writes, no approvals from the phone.
class AgentOfficeController extends ChangeNotifier {
  AgentOfficeController({http.Client? client}) : _client = client ?? http.Client();
  static final AgentOfficeController instance = AgentOfficeController();

  final http.Client _client;
  static const kEndpoint = 'agent_office_endpoint_v1';
  static const kToken = 'agent_office_token_v1';

  OfficeSnapshot snapshot = OfficeSnapshot.disconnected('No provider configured');
  String endpoint = '';
  bool _hasToken = false;
  bool get configured => endpoint.isNotEmpty && _hasToken;
  bool busy = false;

  static String? validateEndpoint(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasAuthority) return 'Enter a full https:// URL';
    if (u.scheme != 'https') return 'Only HTTPS endpoints are allowed';
    if (u.userInfo.isNotEmpty) return 'Do not put credentials in the URL';
    return null;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    endpoint = p.getString(kEndpoint) ?? '';
    _hasToken = (p.getString(kToken) ?? '').isNotEmpty;
    notifyListeners();
  }

  Future<String?> configure(String url, String token) async {
    final err = validateEndpoint(url);
    if (err != null) return err;
    if (token.trim().length < 16) return 'Token looks too short';
    final p = await SharedPreferences.getInstance();
    await p.setString(kEndpoint, url.trim());
    await p.setString(kToken, token.trim());
    endpoint = url.trim();
    _hasToken = true;
    notifyListeners();
    return null;
  }

  Future<void> disconnect() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kEndpoint);
    await p.remove(kToken);
    endpoint = '';
    _hasToken = false;
    snapshot = OfficeSnapshot.disconnected('Provider removed by owner');
    notifyListeners();
  }

  Future<void> refresh() async {
    if (busy) return;
    final p = await SharedPreferences.getInstance();
    final token = p.getString(kToken) ?? '';
    final url = p.getString(kEndpoint) ?? '';
    if (url.isEmpty || token.isEmpty || validateEndpoint(url) != null) {
      snapshot = OfficeSnapshot.disconnected('No authenticated provider configured');
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final res = await _client.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401 || res.statusCode == 403) {
        snapshot = OfficeSnapshot.disconnected('Provider rejected credentials');
      } else if (res.statusCode != 200) {
        snapshot = OfficeSnapshot.disconnected('Provider unavailable (HTTP ${res.statusCode})');
      } else if (res.body.length > 256 * 1024) {
        snapshot = OfficeSnapshot.disconnected('Provider response too large');
      } else {
        final body = jsonDecode(res.body);
        snapshot = body is Map<String, dynamic>
            ? OfficeSnapshot.parse(body, authenticated: true)
            : OfficeSnapshot.disconnected('Provider returned invalid data');
      }
    } on TimeoutException {
      snapshot = OfficeSnapshot.disconnected('Provider timed out');
    } catch (_) {
      // Never surface raw errors (may contain hostnames or tokens).
      snapshot = OfficeSnapshot.disconnected('Provider unreachable');
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
