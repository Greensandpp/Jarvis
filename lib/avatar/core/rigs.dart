import 'dart:math' as math;

import 'math3d.dart';

/// Inputs that drive both rigs each frame (already blended by state).
class RigDrive {
  const RigDrive({
    this.time = 0,
    this.idle = 1,
    this.listening = 0,
    this.thinking = 0,
    this.speaking = 0,
    this.activation = 0,
    this.audio = 0,
    this.speechJaw = 0,
  });
  final double time; // animation clock (s)
  final double idle;
  final double listening;
  final double thinking;
  final double speaking;
  final double activation; // reveal power burst 0..1
  final double audio; // mic / speech level 0..1
  final double speechJaw; // humanoid jaw from visemes 0..1
}

/// A tapered capsule bone used by the PLACEHOLDER humanoid.
class Capsule {
  const Capsule(this.name, this.a, this.b, this.ra, this.rb, {this.material = 0});
  final String name;
  final Vec3 a;
  final Vec3 b;
  final double ra;
  final double rb;
  final int material; // 0 armor, 1 dark under-suit, 2 hand
}

/// PROCEDURAL PLACEHOLDER humanoid in the approved floating pose (arms out,
/// palms up holding energy spheres, legs together pointing down).
///
/// It exists only to exercise the engine (state machine, formation, rings,
/// lightning anchors, face/viseme interface). It is NOT the approved
/// Serpent Guardian model; the final model must be a rigged glTF asset.
class HumanoidRig {
  static const height = 2.0;
  static const feetY = -1.08;
  static const headTopY = 0.93;

  Vec3 root = Vec3.zero; // world offset incl. hover
  double hover = 0;
  double breath = 0;
  double headYaw = 0, headPitch = 0, headRoll = 0;
  double armRaise = 0;
  double fingerCurl = 0;
  final List<Capsule> bones = [];
  Vec3 headCenter = const Vec3(0, 0.79, 0);
  Vec3 headForward = Vec3.forward;
  Vec3 headUp = Vec3.up;
  Vec3 chestCore = const Vec3(0, 0.36, 0.17);
  Vec3 handL = Vec3.zero, handR = Vec3.zero;
  Vec3 orbL = Vec3.zero, orbR = Vec3.zero;

  double _yawT = 0, _pitchT = 0;
  double _nextGlance = 0;

  void update(RigDrive d, double dt) {
    final t = d.time;
    hover = 0.035 * math.sin(t * 1.1) + 0.012 * math.sin(t * 2.3 + 1);
    // Breathing ~14/min idle, faster when speaking/activated.
    final rate = 1.45 + 0.6 * d.speaking + 0.8 * d.activation;
    breath = 0.5 + 0.5 * math.sin(t * rate);
    armRaise = clamp01(0.15 + 0.85 * d.activation + 0.35 * d.listening + 0.2 * d.audio);
    fingerCurl = 0.35 + 0.15 * math.sin(t * 0.9) + 0.1 * d.thinking;

    // Micro head motion: occasional glances while idle, attentive on listen.
    if (t >= _nextGlance) {
      _yawT = (hash01((t * 10).floor()) - 0.5) * 0.35 * d.idle;
      _pitchT = (hash01((t * 10).floor() + 7) - 0.5) * 0.12 * d.idle;
      _nextGlance = t + 2.2 + hash01((t * 3).floor()) * 2.5;
    }
    final yawGoal = _yawT * (1 - d.listening) + 0.25 * d.thinking;
    final pitchGoal = _pitchT + 0.08 * d.thinking - 0.04 * d.listening + 0.03 * math.sin(t * 2.7) * d.speaking;
    headYaw += (yawGoal - headYaw) * approach(dt, 0.35);
    headPitch += (pitchGoal - headPitch) * approach(dt, 0.35);
    headRoll = 0.02 * math.sin(t * 0.7);

    root = Vec3(0, hover, 0);
    _build();
  }

  void _build() {
    bones.clear();
    final r = root;
    final b = breath;
    Vec3 p(double x, double y, double z) => Vec3(x, y, z) + r;
    final chestLift = 0.012 * b;
    final shoulderLift = 0.008 * b;
    final raise = armRaise;

    final pelvis = p(0, -0.06, 0);
    final chest = p(0, 0.37 + chestLift, 0.0);
    final neck = p(0, 0.62 + chestLift, 0.0);
    headCenter = p(0, 0.79 + chestLift, 0.01);
    chestCore = p(0, 0.36 + chestLift, 0.17 + 0.006 * b);

    bones
      ..add(Capsule('abdomen', pelvis, p(0, 0.15, 0), 0.13, 0.15, material: 1))
      ..add(Capsule('chest', p(0, 0.15, 0), chest, 0.15, 0.2 + 0.01 * b))
      ..add(Capsule('neck', chest, neck, 0.07, 0.055, material: 1))
      ..add(Capsule('hips', pelvis, p(0, -0.18, 0), 0.16, 0.14));

    for (final s in const [-1.0, 1.0]) {
      final shoulder = p(0.25 * s, 0.53 + shoulderLift, 0);
      final elbow = p(0.58 * s, 0.30 + 0.16 * raise, 0.05);
      final wrist = p(0.86 * s, 0.07 + 0.22 * raise, 0.13);
      final hand = p(0.95 * s, 0.04 + 0.23 * raise, 0.16);
      bones
        ..add(Capsule('shoulderPad$s', shoulder, p(0.3 * s, 0.5 + shoulderLift, 0), 0.1, 0.085))
        ..add(Capsule('upperArm$s', shoulder, elbow, 0.068, 0.056))
        ..add(Capsule('forearm$s', elbow, wrist, 0.058, 0.042))
        ..add(Capsule('hand$s', wrist, hand, 0.04, 0.034, material: 2));
      // Fingers: three short segments curling upward (palms up).
      for (var f = 0; f < 3; f++) {
        final spread = (f - 1) * 0.035;
        final tip = hand + Vec3(0.06 * s, 0.03 + 0.05 * fingerCurl, spread + 0.02);
        bones.add(Capsule('finger$s$f', hand, tip, 0.014, 0.01, material: 2));
      }
      final orb = hand + Vec3(0.02 * s, 0.11, 0.02);
      if (s < 0) {
        handL = hand;
        orbL = orb;
      } else {
        handR = hand;
        orbR = orb;
      }
      // Legs together, slightly crossed, toes pointed (floating).
      final hip = p(0.085 * s, -0.16, 0);
      final knee = p(0.05 * s, -0.6, 0.04);
      final ankle = p(0.025 * s, -0.98, 0.0);
      final toe = p(0.015 * s, feetY, 0.04);
      bones
        ..add(Capsule('thigh$s', hip, knee, 0.095, 0.07))
        ..add(Capsule('shin$s', knee, ankle, 0.068, 0.045))
        ..add(Capsule('foot$s', ankle, toe, 0.042, 0.018));
    }

    // Head frame from yaw/pitch/roll.
    var f = Vec3.forward.rotate(Vec3.up, headYaw);
    var u = Vec3.up;
    final side = u.cross(f).normalized();
    f = f.rotate(side, headPitch).normalized();
    u = u.rotate(side, headPitch).rotate(f, headRoll).normalized();
    headForward = f;
    headUp = u;
  }

  /// Formation reveal height for progress [k] (feet first).
  static double revealHeight(double k) => lerpD(feetY - 0.1, headTopY + 0.1, clamp01(k));
}

/// Head pose of the serpent (independent from the body).
class SerpentHead {
  Vec3 position = Vec3.zero;
  Vec3 forward = Vec3.forward;
  Vec3 up = Vec3.up;
  double jaw = 0; // 0 closed .. 1 wide open
  double eyeGlow = 1;
  double gazeX = 0, gazeY = 0;
}

/// Procedural articulated serpent: a Catmull-Rom spline spine whose control
/// points coil around the humanoid and rise behind it, animated with
/// travelling S-waves, slow coil drift, independent neck/head/jaw motion.
class SerpentRig {
  SerpentRig({this.segments = 64});

  int segments;
  List<Vec3> controls = const [];
  List<CurveFrame> spine = const [];
  final SerpentHead head = SerpentHead();
  double _yaw = 0.0, _pitch = 0.0;
  double _neck = 0;
  double _jawT = 0;
  double _nextJaw = 3.5;
  double _jawUntil = 0;

  /// Body radius along the spine (s: 0 tail .. 1 neck end).
  static double radiusAt(double s) {
    final tail = smoothstep(0.0, 0.32, s);
    final neckSlim = 1 - 0.28 * smoothstep(0.78, 1.0, s);
    return 0.012 + 0.07 * tail * neckSlim;
  }

  void update(RigDrive d, Vec3 humanoidRoot, double dt) {
    final t = d.time;
    final pts = <Vec3>[];
    // Coil around the humanoid (tail starts low, front-left).
    const coilEnd = 0.62;
    const coilCtl = 14;
    final drift = 0.16 * math.sin(t * 0.23);
    final breathe = 0.03 * math.sin(t * 0.5);
    final waveSpeed = 1.6 + 0.8 * d.thinking + 1.2 * d.activation;
    for (var i = 0; i < coilCtl; i++) {
      final s = i / (coilCtl - 1) * coilEnd;
      final k = s / coilEnd;
      final theta = -0.9 + drift + k * 1.6 * 2 * math.pi;
      final wave = math.sin(2 * math.pi * 2.5 * k - t * waveSpeed);
      final r = 0.6 + 0.07 * math.sin(k * 5 + 1) + breathe + 0.045 * wave;
      final y = -0.95 + 1.08 * k + 0.035 * math.sin(2 * math.pi * 2 * k - t * waveSpeed + 1.3);
      pts.add(Vec3(r * math.sin(theta), y, r * math.cos(theta)) + humanoidRoot * 0.5);
    }
    // Rise behind the humanoid to the neck (upper right), S-shaped sway.
    _neck += ((0.08 * d.listening + 0.05 * d.activation - 0.03 * d.thinking) - _neck) * approach(dt, 0.4);
    final neckBob = 0.05 * math.sin(t * 0.42) + _neck + 0.015 * d.audio;
    final sway = 0.05 * math.sin(t * 0.8) * (1 + d.thinking);
    final rise = <Vec3>[
      Vec3(0.34 + sway * 0.4, 0.32, -0.58),
      Vec3(0.5 - sway * 0.6, 0.55 + neckBob * 0.4, -0.52),
      Vec3(0.66 + sway, 0.8 + neckBob * 0.8, -0.34),
      Vec3(0.74 + sway * 0.6, 0.95 + neckBob, -0.12 + 0.05 * d.listening),
    ];
    for (final q in rise) {
      pts.add(q + humanoidRoot * 0.8);
    }
    controls = pts;
    final samples = sampleSpline(pts, segments);
    spine = parallelTransportFrames(samples, seedNormal: Vec3.up);

    // Head: independent look target.
    final idleYaw = 0.35 * math.sin(t * 0.31) + 0.15 * math.sin(t * 0.87 + 2);
    final idlePitch = 0.12 * math.sin(t * 0.47 + 1);
    final yawGoal = idleYaw * d.idle + (-0.55) * (d.listening + d.activation) + 0.5 * d.thinking + 0.1 * math.sin(t * 1.7) * d.speaking;
    final pitchGoal = idlePitch * d.idle + 0.1 * d.listening + 0.25 * d.thinking - 0.05 * d.activation;
    _yaw += (yawGoal - _yaw) * approach(dt, 0.45);
    _pitch += (pitchGoal - _pitch) * approach(dt, 0.45);
    // Base direction faces right/forward like the reference; yaw turns it
    // towards the camera (+z).
    var fwd = const Vec3(0.85, -0.05, 0.35).normalized().rotate(Vec3.up, -_yaw);
    final side = Vec3.up.cross(fwd).normalized();
    fwd = fwd.rotate(side, -_pitch).normalized();
    final end = spine.last;
    head.position = end.position + end.tangent * 0.06;
    head.forward = (fwd * 0.75 + end.tangent * 0.25).normalized();
    head.up = fwd.cross(side).normalized();
    if (head.up.y < 0) head.up = -head.up;

    // Jaw: occasional controlled opening, wider during the power reveal.
    if (t >= _nextJaw) {
      _jawUntil = t + 0.9;
      _nextJaw = t + 6 + 4 * hash01((t * 7).floor());
    }
    final jawGoal = (t < _jawUntil ? 0.55 : 0.04) * d.idle + 0.85 * d.activation + 0.2 * d.audio * d.speaking;
    _jawT += (clamp01(jawGoal) - _jawT) * approach(dt, 0.12);
    head.jaw = _jawT;
    head.eyeGlow = 0.65 + 0.25 * math.sin(t * 2.2) + 0.35 * d.activation + 0.3 * d.listening + 0.3 * d.audio;
    head.gazeX = 0.3 * math.sin(t * 0.6);
    head.gazeY = 0.2 * math.sin(t * 0.37);
  }
}
