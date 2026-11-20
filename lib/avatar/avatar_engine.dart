import 'dart:math' as math;

enum AvatarState {
  intro,
  formation,
  idle,
  listening,
  thinking,
  speaking,
  closing,
}

/// Monotonic, pausable state machine; resume never integrates background time.
class AvatarTimeline {
  AvatarTimeline({bool intro = true})
    : state = intro ? AvatarState.intro : AvatarState.idle;
  AvatarState state;
  AvatarState requested = AvatarState.idle;
  double age = 0, time = 0;
  bool paused = false, closed = false;
  double get progress => switch (state) {
    AvatarState.intro => (age / .8).clamp(0, 1),
    AvatarState.formation => (age / 1.4).clamp(0, 1),
    AvatarState.closing => (1 - age / .6).clamp(0, 1),
    _ => 1,
  };
  void request(AvatarState next) {
    requested = next;
    if (state != AvatarState.intro &&
        state != AvatarState.formation &&
        state != AvatarState.closing)
      _set(next);
  }

  void close() {
    closed = false;
    _set(AvatarState.closing);
  }

  void restart() {
    closed = false;
    _set(AvatarState.intro);
  }

  void _set(AvatarState next) {
    if (state != next) {
      state = next;
      age = 0;
    }
  }

  void tick(double dt) {
    if (paused || closed || !dt.isFinite || dt < 0) return;
    dt = dt.clamp(0, .1);
    age += dt;
    time += dt;
    if (state == AvatarState.intro && age >= .8) _set(AvatarState.formation);
    if (state == AvatarState.formation && age >= 1.4) _set(requested);
    if (state == AvatarState.closing && age >= .6) closed = true;
  }
}

/// Timestamped audio amplitude or real viseme timings. No pseudo-phoneme
/// inference from Tamil spelling. Unavailable audio yields a closed mouth.
class FaceFrame {
  const FaceFrame({this.jaw = 0, this.round = 0, this.wide = 0});
  final double jaw, round, wide;
}

class VisemeCue {
  const VisemeCue(this.start, this.end, this.frame);
  final Duration start, end;
  final FaceFrame frame;
}

class AudioFaceDriver {
  double _level = 0;
  FaceFrame sample({
    required double dt,
    required bool speaking,
    double? rms,
    Duration position = Duration.zero,
    List<VisemeCue> cues = const [],
  }) {
    if (!speaking) {
      _level = 0;
      return const FaceFrame();
    }
    for (final cue in cues) {
      if (position >= cue.start && position < cue.end) return cue.frame;
    }
    final target = rms != null && rms.isFinite ? rms.clamp(0.0, 1.0) : 0.0;
    _level += (target - _level) * (dt.clamp(0, .1) * 16).clamp(0, 1);
    return FaceFrame(jaw: _level, wide: _level * .3);
  }
}

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  V3 operator +(V3 p) => V3(x + p.x, y + p.y, z + p.z);
  V3 operator -(V3 p) => V3(x - p.x, y - p.y, z - p.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit => length < 1e-8 ? const V3(0, 1, 0) : this * (1 / length);
  V3 cross(V3 p) => V3(y * p.z - z * p.y, z * p.x - x * p.z, x * p.y - y * p.x);
  double dot(V3 p) => x * p.x + y * p.y + z * p.z;
}

/// Catmull–Rom curve through an animated coil. The head/neck follow the same
/// spline as the tube, rather than an independently translated snake image.
class SerpentSpline {
  SerpentSpline(double time)
    : points = [
        for (var i = 0; i < 12; i++)
          V3(
            math.cos(i * .76 + time * .22) * (.75 - i * .015),
            1.3 - i * .22,
            math.sin(i * .76 + time * .22) * .55,
          ),
        V3(.68 + math.sin(time * .7) * .06, -1.3, .28),
        V3(.82 + math.sin(time * .7) * .07, -1.48, .4),
      ];
  final List<V3> points;
  V3 at(double u) {
    final f = u.clamp(0.0, 1.0) * (points.length - 3);
    final i = math.min(f.floor(), points.length - 4), t = f - i;
    final a = points[i],
        b = points[i + 1],
        c = points[i + 2],
        d = points[i + 3];
    return (b * 2 +
            (c - a) * t +
            (a * 2 - b * 5 + c * 4 - d) * (t * t) +
            (b * 3 - a - c * 3 + d) * (t * t * t)) *
        .5;
  }
}
