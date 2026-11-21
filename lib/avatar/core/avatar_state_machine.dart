import 'math3d.dart';

/// Lifecycle / conversation states of a JARVIS avatar.
///
/// INTRO → MATERIALIZING → IDLE run automatically. LISTENING, THINKING and
/// SPEAKING follow the shared JARVIS phase. CLOSING dissolves the avatar.
enum AvatarState { intro, materializing, idle, listening, thinking, speaking, closing }

/// Timeline constants (seconds at animation speed 1.0). Mirrors the approved
/// storyboard: dark intro 1.5 s, humanoid 1.7 s, serpent 1.3 s, reveal 1.5 s.
class AvatarTimeline {
  static const intro = 1.5;
  static const humanoid = 1.7;
  static const serpent = 1.3;
  static const reveal = 1.5;
  static const materializing = humanoid + serpent + reveal; // 4.5
  static const closing = 1.6;
  static const blend = 0.4;
}

/// Pure-Dart, renderer-independent avatar state machine.
///
/// The renderer (procedural Canvas today, Filament/glTF later) only reads the
/// derived values (formation progress, state weights); it never decides state.
class AvatarStateMachine {
  AvatarStateMachine({bool skipIntro = false}) {
    if (skipIntro) {
      _state = AvatarState.idle;
      _previous = AvatarState.idle;
      _blend = 1;
    }
  }

  AvatarState _state = AvatarState.intro;
  AvatarState _previous = AvatarState.intro;
  double _stateTime = 0;
  double _blend = 1;
  double _clock = 0;
  AvatarState? _pending;
  bool _closed = false;
  final List<AvatarState> history = <AvatarState>[AvatarState.intro];

  /// Called on every transition (for sounds, analytics, tests).
  void Function(AvatarState from, AvatarState to)? onTransition;

  AvatarState get state => _state;
  AvatarState get previous => _previous;
  double get stateTime => _stateTime;
  double get clock => _clock;
  AvatarState? get pending => _pending;

  /// True once CLOSING has fully finished (avatar dissolved).
  bool get closed => _closed;

  /// 0..1 progress of the cross-fade from [previous] to [state].
  double get blend => _blend;

  static bool isConversational(AvatarState s) =>
      s == AvatarState.idle || s == AvatarState.listening ||
      s == AvatarState.thinking || s == AvatarState.speaking;

  /// Whether a direct transition is permitted.
  static bool canTransition(AvatarState from, AvatarState to) {
    if (from == to) return false;
    return switch (from) {
      AvatarState.intro => to == AvatarState.materializing || to == AvatarState.closing,
      AvatarState.materializing => to == AvatarState.idle || to == AvatarState.closing,
      AvatarState.closing => to == AvatarState.intro,
      AvatarState.idle || AvatarState.listening || AvatarState.thinking || AvatarState.speaking =>
        isConversational(to) || to == AvatarState.closing,
    };
  }

  void _enter(AvatarState next) {
    final from = _state;
    _previous = _state;
    _state = next;
    _stateTime = 0;
    _blend = 0;
    if (next == AvatarState.intro) _closed = false;
    history.add(next);
    if (history.length > 64) history.removeAt(0);
    onTransition?.call(from, next);
  }

  /// Requests a state. During INTRO/MATERIALIZING a conversational request
  /// is queued so the formation is never cut short; CLOSING always applies.
  /// Returns true if the request was applied or queued.
  bool request(AvatarState next) {
    if (next == AvatarState.intro) {
      replayIntro();
      return true;
    }
    if (_state == AvatarState.intro || _state == AvatarState.materializing) {
      if (next == AvatarState.closing) {
        _pending = null;
        _enter(AvatarState.closing);
        return true;
      }
      if (isConversational(next)) {
        _pending = next;
        return true;
      }
      return false;
    }
    if (_state == next) return true;
    if (!canTransition(_state, next)) return false;
    _enter(next);
    return true;
  }

  /// Restarts the full intro + formation sequence.
  void replayIntro() {
    _pending = null;
    _enter(AvatarState.intro);
  }

  /// Maps the shared JARVIS phase name (idle/listening/thinking/executing/
  /// speaking) to an avatar state and requests it.
  bool applyPhaseName(String phase) => request(stateForPhase(phase));

  static AvatarState stateForPhase(String phase) => switch (phase) {
        'listening' => AvatarState.listening,
        'thinking' || 'executing' => AvatarState.thinking,
        'speaking' => AvatarState.speaking,
        _ => AvatarState.idle,
      };

  /// Advances time by [dt] seconds (already scaled by animation speed).
  void tick(double dt) {
    if (!(dt > 0)) return;
    if (dt > 0.25) dt = 0.25; // never jump the timeline after a stall
    _clock += dt;
    _stateTime += dt;
    _blend = clamp01(_blend + dt / AvatarTimeline.blend);
    switch (_state) {
      case AvatarState.intro:
        if (_stateTime >= AvatarTimeline.intro) _enter(AvatarState.materializing);
      case AvatarState.materializing:
        if (_stateTime >= AvatarTimeline.materializing) {
          final next = _pending ?? AvatarState.idle;
          _pending = null;
          _enter(next);
        }
      case AvatarState.closing:
        if (_stateTime >= AvatarTimeline.closing) _closed = true;
      case AvatarState.idle:
      case AvatarState.listening:
      case AvatarState.thinking:
      case AvatarState.speaking:
        break;
    }
  }

  /// Platform / rings power-on, 0..1.
  double get platformPower {
    switch (_state) {
      case AvatarState.intro:
        return smoothstep(0, AvatarTimeline.intro, _stateTime);
      case AvatarState.closing:
        return 1 - smoothstep(AvatarTimeline.closing * 0.5, AvatarTimeline.closing, _stateTime);
      default:
        return 1;
    }
  }

  /// Humanoid assembly, 0 (particles) .. 1 (fully formed). Feet first.
  double get humanoidFormation {
    switch (_state) {
      case AvatarState.intro:
        return 0;
      case AvatarState.materializing:
        return smoothstep(0, AvatarTimeline.humanoid, _stateTime);
      case AvatarState.closing:
        return 1 - smoothstep(AvatarTimeline.closing * 0.25, AvatarTimeline.closing, _stateTime);
      default:
        return 1;
    }
  }

  /// Serpent assembly, tail first.
  double get serpentFormation {
    switch (_state) {
      case AvatarState.intro:
        return 0;
      case AvatarState.materializing:
        return smoothstep(AvatarTimeline.humanoid, AvatarTimeline.humanoid + AvatarTimeline.serpent, _stateTime);
      case AvatarState.closing:
        return 1 - smoothstep(0, AvatarTimeline.closing * 0.75, _stateTime);
      default:
        return 1;
    }
  }

  /// Power-activation burst during the first full reveal (0 → 1 → ~0.25).
  double get activation {
    if (_state != AvatarState.materializing) return 0;
    const start = AvatarTimeline.humanoid + AvatarTimeline.serpent;
    final t = _stateTime - start;
    if (t <= 0) return 0;
    final rise = smoothstep(0, 0.45, t);
    final fall = 1 - 0.75 * smoothstep(0.6, AvatarTimeline.reveal, t);
    return rise * fall;
  }

  /// Blended weight of [s] in the current pose (cross-fade from previous).
  double weight(AvatarState s) {
    final b = _blend * _blend * (3 - 2 * _blend);
    var w = 0.0;
    if (_state == s) w += b;
    if (_previous == s) w += 1 - b;
    return w;
  }

  /// Weight of "resting" behaviour: everything that is not an active
  /// conversation state counts as idle for motion purposes.
  double get idleLike => 1 - weight(AvatarState.listening) - weight(AvatarState.thinking) - weight(AvatarState.speaking);
}
