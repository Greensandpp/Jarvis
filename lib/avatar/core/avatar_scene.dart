import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_reactive.dart';
import 'avatar_settings.dart';
import 'avatar_state_machine.dart';
import 'math3d.dart';
import 'render_list.dart';
import 'rigs.dart';
import 'viseme.dart';

/// Quality budget derived from [AvatarPerformanceMode].
class SceneBudget {
  const SceneBudget({required this.sides, required this.serpentSegments, required this.maxParticles,
      required this.ringSegments, required this.blur, required this.targetFps});
  final int sides;
  final int serpentSegments;
  final int maxParticles;
  final int ringSegments;
  final bool blur;
  final int targetFps;

  static SceneBudget of(AvatarPerformanceMode m) => switch (m) {
        AvatarPerformanceMode.quality =>
          const SceneBudget(sides: 12, serpentSegments: 84, maxParticles: 800, ringSegments: 96, blur: true, targetFps: 60),
        AvatarPerformanceMode.balanced =>
          const SceneBudget(sides: 10, serpentSegments: 64, maxParticles: 440, ringSegments: 72, blur: true, targetFps: 60),
        AvatarPerformanceMode.battery =>
          const SceneBudget(sides: 7, serpentSegments: 40, maxParticles: 160, ringSegments: 48, blur: false, targetFps: 30),
      };
}

/// Particle pool (structure of arrays, no per-frame allocation).
class _Particles {
  _Particles(this.capacity)
      : px = Float64List(capacity), py = Float64List(capacity), pz = Float64List(capacity),
        vx = Float64List(capacity), vy = Float64List(capacity), vz = Float64List(capacity),
        life = Float64List(capacity), maxLife = Float64List(capacity), size = Float64List(capacity),
        colorIdx = Int8List(capacity), kind = Int8List(capacity);
  final int capacity;
  final Float64List px, py, pz, vx, vy, vz, life, maxLife, size;
  final Int8List colorIdx, kind; // kind 0 glitter, 1 spark, 2 formation
  int alive = 0;
  int _seed = 1;

  double rnd() => hash01(_seed++);

  void spawn(Vec3 p, Vec3 v, double lifeS, double sz, int color, int k) {
    if (alive >= capacity) return;
    final i = alive++;
    px[i] = p.x; py[i] = p.y; pz[i] = p.z;
    vx[i] = v.x; vy[i] = v.y; vz[i] = v.z;
    life[i] = 0; maxLife[i] = lifeS; size[i] = sz; colorIdx[i] = color; kind[i] = k;
  }

  void step(double dt, double t) {
    var i = 0;
    while (i < alive) {
      life[i] += dt;
      if (life[i] >= maxLife[i]) {
        final last = --alive;
        px[i] = px[last]; py[i] = py[last]; pz[i] = pz[last];
        vx[i] = vx[last]; vy[i] = vy[last]; vz[i] = vz[last];
        life[i] = life[last]; maxLife[i] = maxLife[last]; size[i] = size[last];
        colorIdx[i] = colorIdx[last]; kind[i] = kind[last];
        continue;
      }
      if (kind[i] == 0) {
        // Glitter: lazy swirl around the vertical axis + gentle rise.
        final ang = 0.18 * dt;
        final x = px[i], z = pz[i];
        px[i] = x * math.cos(ang) - z * math.sin(ang);
        pz[i] = x * math.sin(ang) + z * math.cos(ang);
        py[i] += vy[i] * dt;
      } else {
        final drag = kind[i] == 1 ? 0.9 : 0.6;
        vx[i] *= 1 - drag * dt; vy[i] *= 1 - drag * dt; vz[i] *= 1 - drag * dt;
        px[i] += vx[i] * dt; py[i] += vy[i] * dt; pz[i] += vz[i] * dt;
      }
      i++;
    }
  }
}

class _Bolt {
  _Bolt(this.points, this.life);
  final List<Vec3> points;
  final double life;
  double age = 0;
}

/// Complete procedural avatar scene: state machine + rigs + VFX.
///
/// Pure Dart. The Flutter widget feeds it time, JARVIS phase, audio levels
/// and spoken text, then asks for a [RenderList] to paint.
class AvatarScene {
  AvatarScene({AvatarSettings settings = AvatarSettings.defaults, bool skipIntro = false})
      : machine = AvatarStateMachine(skipIntro: skipIntro) {
    applySettings(settings);
  }

  final AvatarStateMachine machine;
  final AudioReactiveBus audio = AudioReactiveBus();
  final ProceduralFaceRig face = ProceduralFaceRig();
  final HumanoidRig humanoid = HumanoidRig();
  late SerpentRig serpent;
  late _Particles _particles;
  final List<_Bolt> _bolts = [];
  AvatarSettings settings = AvatarSettings.defaults;
  SceneBudget budget = SceneBudget.of(AvatarPerformanceMode.balanced);

  VisemeTimeline _speech = VisemeTimeline.empty;
  double _speechStart = -1;
  double _time = 0;
  double _boltTimer = 0;
  double _blink = 0;
  double _nextBlink = 2.5;
  RigDrive _drive = const RigDrive();
  int _rng = 7;

  double get time => _time;
  RigDrive get drive => _drive;
  bool get speakingTimelineActive => _speechStart >= 0 && _time - _speechStart < _speech.duration;

  void applySettings(AvatarSettings s) {
    final perfChanged = s.performance != settings.performance;
    settings = s;
    budget = SceneBudget.of(s.performance);
    final cap = (budget.maxParticles * (0.25 + 0.75 * s.particleDensity)).round();
    if (perfChanged || !_hasParticles || _particles.capacity != cap) {
      _particles = _Particles(cap < 16 ? 16 : cap);
      _hasParticles = true;
    }
    if (perfChanged || !_hasSerpent) {
      serpent = SerpentRig(segments: budget.serpentSegments);
      _hasSerpent = true;
    }
  }

  bool _hasParticles = false;
  bool _hasSerpent = false;

  /// Starts mouth animation for a spoken line (Tamil / Tanglish / English).
  void speak(String text, {double rate = 1.0}) {
    _speech = TamilVisemeMapper(rate: rate).map(text);
    _speechStart = _time;
  }

  void stopSpeech() {
    _speech = VisemeTimeline.empty;
    _speechStart = -1;
  }

  double _r() => hash01(_rng++);

  /// Advances the simulation. [phase] is the JARVIS phase name.
  void update(double realDt, {String phase = 'idle', double micLevel = 0}) {
    final dt = (realDt.isFinite && realDt > 0 ? realDt : 0.0).clamp(0.0, 0.1).toDouble() * settings.speed;
    _time += dt;
    machine.applyPhaseName(phase);
    machine.tick(dt);

    // Audio hooks: mic while listening, viseme envelope while speaking.
    audio.pushMic(machine.state == AvatarState.listening ? micLevel : micLevel * 0.3);
    final st = _speechStart >= 0 ? _time - _speechStart : -1.0;
    final speaking = machine.weight(AvatarState.speaking);
    audio.pushOutput(speaking > 0.05 ? _speech.amplitude(st) * speaking : 0);
    audio.tick(dt);

    // Face: visemes + blink + gaze.
    if (speaking > 0.02 && st >= 0 && st < _speech.duration) {
      final w = _speech.sample(st);
      face.setVisemeWeights(w);
      face.setJawOpen(_speech.jawOpen(st) * (0.55 + 0.45 * speaking));
    } else {
      // Micro-movement so the face never looks frozen.
      face.setVisemeWeights(const {Viseme.sil: 1});
      final micro = 0.04 + 0.03 * math.sin(_time * 1.3) * math.sin(_time * 0.37);
      face.setJawOpen(micro + (speaking > 0.05 ? 0.18 * audio.output : 0));
    }
    if (_time >= _nextBlink) {
      _blink = 1;
      _nextBlink = _time + 2.8 + 3.2 * _r();
    }
    _blink = (_blink - dt * 7).clamp(0.0, 1.0).toDouble();
    face.setBlink(_blink > 0.5 ? (1 - _blink) * 2 : _blink * 2);
    face.setGaze(0.25 * math.sin(_time * 0.5), 0.1 * math.sin(_time * 0.31));
    face.setExpression('focus', machine.weight(AvatarState.thinking));

    _drive = RigDrive(
      time: _time,
      idle: clamp01(machine.idleLike),
      listening: machine.weight(AvatarState.listening),
      thinking: machine.weight(AvatarState.thinking),
      speaking: speaking,
      activation: machine.activation,
      audio: audio.level,
      speechJaw: face.jawOpen,
    );
    humanoid.update(_drive, dt);
    serpent.update(_drive, humanoid.root, dt);

    _spawnParticles(dt);
    _particles.step(dt, _time);
    _updateBolts(dt);
  }

  // ---------------------------------------------------------------- VFX sim

  void _spawnParticles(double dt) {
    final p = _particles;
    final power = machine.platformPower;
    // Ambient glitter keeps ~55% of the pool.
    final glitterTarget = (p.capacity * 0.55 * (0.2 + 0.8 * power)).round();
    var glitterAlive = 0;
    for (var i = 0; i < p.alive; i++) {
      if (p.kind[i] == 0) glitterAlive++;
    }
    var want = math.min(glitterTarget - glitterAlive, (p.capacity * 0.08).round() + 1);
    while (want-- > 0) {
      final a = _r() * math.pi * 2, rad = 0.2 + 1.25 * math.sqrt(_r());
      p.spawn(Vec3(rad * math.cos(a), -1.25 + 2.6 * _r(), rad * math.sin(a) * 0.8),
          Vec3(0, 0.02 + 0.06 * _r(), 0), 2.5 + 3.5 * _r(), 0.6 + 1.6 * _r(), (_r() * 4).floor(), 0);
    }

    // Formation particles at the humanoid / serpent frontier.
    final hf = machine.humanoidFormation, sf = machine.serpentFormation;
    final forming = machine.state == AvatarState.materializing || machine.state == AvatarState.closing;
    if (forming && hf > 0.001 && hf < 0.999) {
      final reveal = HumanoidRig.revealHeight(hf);
      for (var n = 0; n < _ci((90 * dt * 60).round(), 1, 12); n++) {
        final pt = _pointOnHumanoidNear(reveal);
        if (pt == null) continue;
        final out = Vec3(_r() - 0.5, 0.4 + _r(), _r() - 0.5) * 0.35;
        p.spawn(pt, out, 0.5 + 0.6 * _r(), 1.2 + 1.8 * _r(), _r() < 0.6 ? 1 : 0, 2);
      }
    }
    if (forming && sf > 0.001 && sf < 0.999 && serpent.spine.isNotEmpty) {
      for (var n = 0; n < 6; n++) {
        final idx = _ci((sf * (serpent.spine.length - 1)).round(), 0, serpent.spine.length - 1);
        final f = serpent.spine[idx];
        final a = _r() * math.pi * 2;
        final r = SerpentRig.radiusAt(idx / (serpent.spine.length - 1)) * 1.4;
        final pt = f.position + f.normal * (math.cos(a) * r) + f.binormal * (math.sin(a) * r);
        p.spawn(pt, (f.normal * math.cos(a) + f.binormal * math.sin(a)) * 0.25, 0.5 + 0.5 * _r(),
            1.0 + 1.8 * _r(), _r() < 0.5 ? 0 : 1, 2);
      }
    }
    // Rising energy swirl during intro / materializing.
    if (machine.state == AvatarState.intro || machine.state == AvatarState.materializing) {
      for (var n = 0; n < 3; n++) {
        final a = _r() * math.pi * 2;
        p.spawn(Vec3(0.55 * math.cos(a), -1.2, 0.45 * math.sin(a)),
            Vec3(-math.sin(a) * 0.6, 0.9 + 0.8 * _r(), math.cos(a) * 0.5), 1.0 + _r(), 1.0 + 1.4 * _r(),
            (_r() * 4).floor(), 1);
      }
    }
    // Sparks from the orbs and chest core react to activation / audio.
    final sparkRate = (machine.state == AvatarState.closing ? 0 : 1) *
        (0.6 + 10 * _drive.activation + 6 * audio.level + 3 * audio.onset) * settings.particleDensity;
    var sparks = sparkRate * dt * 4;
    while (sparks > 0) {
      if (_r() < sparks) {
        final src = switch ((_r() * 3).floor()) { 0 => humanoid.orbL, 1 => humanoid.orbR, _ => humanoid.chestCore };
        final v = Vec3(_r() - 0.5, _r() - 0.2, _r() - 0.5) * 1.3;
        p.spawn(src, v, 0.25 + 0.4 * _r(), 1.0 + 1.2 * _r(), _r() < 0.7 ? 3 : 2, 1);
      }
      sparks -= 1;
    }
  }

  Vec3? _pointOnHumanoidNear(double y) {
    final bones = humanoid.bones;
    if (bones.isEmpty) return null;
    for (var attempt = 0; attempt < 8; attempt++) {
      final b = bones[_ci((_r() * bones.length).floor(), 0, bones.length - 1)];
      final t = _r();
      final c = b.a.lerp(b.b, t);
      if ((c.y - y).abs() > 0.09) continue;
      final r = lerpD(b.ra, b.rb, t);
      final a = _r() * math.pi * 2;
      return c + Vec3(math.cos(a) * r, 0, math.sin(a) * r);
    }
    return null;
  }

  void _updateBolts(double dt) {
    for (final b in _bolts) {
      b.age += dt;
    }
    _bolts.removeWhere((b) => b.age >= b.life);
    if (machine.humanoidFormation < 0.95 || settings.lightning <= 0) return;
    final rate = settings.lightning *
        (0.25 + 9 * _drive.activation + 3.5 * audio.output + 2.5 * audio.mic + 1.2 * _drive.thinking);
    _boltTimer += dt * rate;
    while (_boltTimer >= 1) {
      _boltTimer -= 1;
      final choice = (_r() * 5).floor();
      final spine = serpent.spine;
      final serpentPt = spine.isEmpty ? humanoid.headCenter : spine[_ci((spine.length * (0.45 + 0.4 * _r())).floor(), 0, spine.length - 1)].position;
      final a = humanoid.chestCore;
      final b = switch (choice) {
        0 => humanoid.orbL,
        1 => humanoid.orbR,
        2 => serpentPt,
        3 => Vec3(math.cos(_r() * 6.28) * 0.95, -1.18, math.sin(_r() * 6.28) * 0.8),
        _ => _r() < 0.5 ? humanoid.orbL : serpentPt,
      };
      final from = choice == 4 ? humanoid.orbR : a;
      _bolts.add(_Bolt(_jagged(from, b, 4, 0.12), 0.09 + 0.08 * _r()));
    }
    if (_bolts.length > 8) _bolts.removeRange(0, _bolts.length - 8);
  }

  List<Vec3> _jagged(Vec3 a, Vec3 b, int depth, double amp) {
    var pts = <Vec3>[a, b];
    var d = amp * (a - b).length;
    for (var k = 0; k < depth; k++) {
      final next = <Vec3>[pts.first];
      for (var i = 0; i < pts.length - 1; i++) {
        final m = pts[i].lerp(pts[i + 1], 0.5) + Vec3(_r() - 0.5, _r() - 0.5, _r() - 0.5) * d;
        next..add(m)..add(pts[i + 1]);
      }
      pts = next;
      d *= 0.55;
    }
    return pts;
  }

  // -------------------------------------------------------------- rendering

  /// Builds the projected, shaded draw list for a canvas of [width]x[height].
  RenderList build(double width, double height) {
    final out = RenderList()
      ..background = settings.backgroundEffects
      ..backgroundPower = machine.platformPower
      ..backgroundTint = settings.primaryColor
      ..allowBlur = budget.blur;
    if (width <= 0 || height <= 0) return out;

    final s = settings;
    const fov = 0.8;
    final dist = 3.25 / s.scale / (2 * math.tan(fov / 2));
    final push = 0.06 * (1 - machine.humanoidFormation) * (machine.state == AvatarState.closing ? 0 : 1);
    final cam = PerspectiveCamera(
      width: width,
      height: height,
      distance: dist * (1 + push),
      fovY: fov,
      target: const Vec3(0, -0.12, 0),
      yaw: 0.05 * math.sin(_time * 0.13),
      pitch: 0.04 + 0.015 * math.sin(_time * 0.09),
    );
    final ox = s.offsetX * width, oy = s.offsetY * height;
    ({double x, double y, double depth, double scale}) proj(Vec3 p) {
      final r = cam.project(p);
      return (x: r.x + ox, y: r.y + oy, depth: r.depth, scale: r.scale);
    }

    final centerDepth = cam.project(humanoid.root).depth;
    final glow = s.glow;
    final prim = s.primaryColor, sec = s.secondaryColor, part = s.particleColor, acc = s.accentColor;
    final palette = [prim, sec, part, acc];

    // 1) Platform rings.
    _platform(out, proj, cam, palette);
    // 2) Ribbons + orbit rings, back halves.
    final ribbons = _ribbons(proj, centerDepth, palette);
    final orbits = _orbitRings(proj, centerDepth, palette);
    for (final op in ribbons.back) {
      out.add(op);
    }
    for (final op in orbits.back) {
      out.add(op);
    }
    // 3) Serpent (holographic, additive) — back half.
    final serpentOps = _serpentMesh(proj, cam, centerDepth);
    if (serpentOps.back != null) out.add(serpentOps.back!);
    // 4) Particles behind.
    final sprites = _sprites(proj, centerDepth, palette);
    if (sprites.back != null) out.add(sprites.back!);
    // 5) Humanoid placeholder (opaque metallic) + emissive details.
    final humanOp = _humanoidMesh(proj, cam);
    if (humanOp != null) out.add(humanOp);
    _humanoidEmissive(out, proj, palette);
    // 6) Serpent front half + head + eyes.
    if (serpentOps.front != null) out.add(serpentOps.front!);
    _serpentHeadFx(out, proj, palette);
    // 7) Front ribbons, orbits, particles, lightning.
    for (final op in ribbons.front) {
      out.add(op);
    }
    for (final op in orbits.front) {
      out.add(op);
    }
    if (sprites.front != null) out.add(sprites.front!);
    _lightning(out, proj, palette);
    // Reveal flash.
    final act = machine.activation;
    if (act > 0.02) {
      final c = proj(humanoid.chestCore);
      out.add(GlowOp(c.x, c.y, c.scale * (0.6 + 0.8 * act), scaleRgb(sec, 0.35 * act * glow), core: 0.2));
    }
    return out;
  }

  void _platform(RenderList out, ({double x, double y, double depth, double scale}) Function(Vec3) proj,
      PerspectiveCamera cam, List<int> pal) {
    final power = machine.platformPower;
    if (power <= 0.001) return;
    const y = -1.22;
    final n = budget.ringSegments;
    final radii = [0.32, 0.58, 0.82, 1.02];
    for (var k = 0; k < radii.length; k++) {
      final grow = smoothstep(k * 0.15, 0.55 + k * 0.15, power);
      if (grow <= 0) continue;
      final rad = radii[k] * (0.6 + 0.4 * grow);
      final spin = _time * (k.isEven ? 0.35 : -0.22) * (1 + _drive.activation * 2);
      final dashed = k.isOdd;
      final pts = <double>[];
      Vec3 ringAt(int i) {
        final a = spin + i / n * math.pi * 2;
        return Vec3(rad * math.cos(a), y, rad * math.sin(a));
      }
      for (var i = 0; i < n; i++) {
        if (dashed) {
          if ((i ~/ 3).isOdd) continue;
          final p = proj(ringAt(i)), q = proj(ringAt(i + 1));
          pts..add(p.x)..add(p.y)..add(q.x)..add(q.y);
        } else {
          final p = proj(ringAt(i));
          pts..add(p.x)..add(p.y);
          if (i == n - 1) {
            final q = proj(ringAt(n));
            pts..add(q.x)..add(q.y);
          }
        }
      }
      final col = pal[k % 2 == 0 ? 0 : 1];
      final a = (0.35 + 0.45 * grow) * power * settings.glow;
      final f = Float32List.fromList(pts);
      if (budget.blur) out.add(LineOp(f, scaleRgb(col, a * 0.6), 6, mode: dashed ? LineMode.pairs : LineMode.strip, blur: 4));
      out.add(LineOp(f, scaleRgb(col, a), 1.6, mode: dashed ? LineMode.pairs : LineMode.strip));
    }
    final c = proj(const Vec3(0, y, 0));
    out.add(GlowOp(c.x, c.y, c.scale * 0.9 * power, scaleRgb(pal[0], 0.35 * power * settings.glow), core: 0.15));
    // Upward light beam under the feet.
    final f = proj(const Vec3(0, -1.05, 0));
    out.add(GlowOp(f.x, (c.y + f.y) / 2, c.scale * 0.32 * power, scaleRgb(pal[1], 0.3 * power * settings.glow)));
  }

  ({List<RenderOp> back, List<RenderOp> front}) _ribbons(
      ({double x, double y, double depth, double scale}) Function(Vec3) proj, double centerDepth, List<int> pal) {
    final back = <RenderOp>[], front = <RenderOp>[];
    final reveal = clamp01(machine.platformPower * 0.4 + machine.humanoidFormation * 0.6);
    if (reveal <= 0.01) return (back: back, front: front);
    const ribbonsN = 3;
    final steps = budget.ringSegments;
    for (var r = 0; r < ribbonsN; r++) {
      final bp = <double>[], fp = <double>[];
      final phase = r * 2.1;
      final speed = 0.55 + 0.2 * r + 0.6 * _drive.activation + 0.4 * _drive.thinking;
      for (var i = 0; i < steps; i++) {
        final u0 = i / steps, u1 = (i + 1) / steps;
        if (u1 > reveal) break;
        Vec3 at(double u) {
          final a = phase + u * 2.6 * math.pi * 2 + _time * speed;
          final rad = 0.62 + 0.14 * math.sin(u * 7 + _time * 0.8 + r) + 0.05 * _drive.audio;
          return Vec3(rad * math.cos(a), -1.15 + 2.25 * u, rad * math.sin(a) * 0.85) + humanoid.root * 0.6;
        }
        final p0 = at(u0), p1 = at(u1);
        final a = proj(p0), b = proj(p1);
        final list = (a.depth + b.depth) / 2 > centerDepth ? bp : fp;
        list..add(a.x)..add(a.y)..add(b.x)..add(b.y);
      }
      final col = pal[r % 3 == 2 ? 2 : r % 3];
      final a = 0.55 * settings.glow;
      if (bp.isNotEmpty) {
        final f = Float32List.fromList(bp);
        back.add(LineOp(f, scaleRgb(col, a * 0.5), 2.2, mode: LineMode.pairs));
      }
      if (fp.isNotEmpty) {
        final f = Float32List.fromList(fp);
        if (budget.blur) front.add(LineOp(f, scaleRgb(col, a * 0.45), 7, mode: LineMode.pairs, blur: 5));
        front.add(LineOp(f, scaleRgb(col, a), 2.4, mode: LineMode.pairs));
      }
    }
    return (back: back, front: front);
  }

  ({List<RenderOp> back, List<RenderOp> front}) _orbitRings(
      ({double x, double y, double depth, double scale}) Function(Vec3) proj, double centerDepth, List<int> pal) {
    final back = <RenderOp>[], front = <RenderOp>[];
    final vis = machine.humanoidFormation;
    if (vis <= 0.05) return (back: back, front: front);
    final n = budget.ringSegments;
    final specs = [(-0.05, 0.98, 0.32, 0.4), (0.38, 0.72, -0.42, -0.65)];
    for (var k = 0; k < specs.length; k++) {
      final (cy, rad, tilt, spd) = specs[k];
      final spin = _time * spd * (1 + 1.5 * _drive.activation);
      final bp = <double>[], fp = <double>[];
      for (var i = 0; i < n; i++) {
        if ((i ~/ 2) % 3 == 2) continue; // holographic dash gaps
        Vec3 at(double a) {
          final x = rad * math.cos(a), z = rad * math.sin(a);
          // Tilt around x axis.
          return Vec3(x, cy + z * math.sin(tilt), z * math.cos(tilt)) + humanoid.root;
        }
        final a0 = spin + i / n * math.pi * 2, a1 = spin + (i + 1) / n * math.pi * 2;
        final p = proj(at(a0)), q = proj(at(a1));
        final list = (p.depth + q.depth) / 2 > centerDepth ? bp : fp;
        list..add(p.x)..add(p.y)..add(q.x)..add(q.y);
      }
      final col = pal[k == 0 ? 1 : 3];
      final a = 0.5 * vis * settings.glow * (1 + 0.5 * _drive.activation);
      if (bp.isNotEmpty) back.add(LineOp(Float32List.fromList(bp), scaleRgb(col, a * 0.5), 1.4, mode: LineMode.pairs));
      if (fp.isNotEmpty) front.add(LineOp(Float32List.fromList(fp), scaleRgb(col, a), 1.6, mode: LineMode.pairs));
    }
    return (back: back, front: front);
  }

  ({TriOp? back, TriOp? front}) _serpentMesh(
      ({double x, double y, double depth, double scale}) Function(Vec3) proj, PerspectiveCamera cam, double centerDepth) {
    final spine = serpent.spine;
    final form = machine.serpentFormation;
    if (spine.length < 2 || form <= 0.001) return (back: null, front: null);
    final m = budget.sides;
    final n = spine.length;
    final visibleRings = (form * (n - 1)).ceil() + 1;
    final rings = math.min(n, visibleRings);
    final hf = _HeadMesh.build(serpent.head, m, form > 0.97 ? 1 : 0);
    final vCount = rings * m + hf.vertices.length;
    final pos = Float32List(vCount * 2);
    final col = Int32List(vCount);
    final depth = Float64List(vCount);
    final prim = settings.primaryColor, sec = settings.secondaryColor;
    final glow = settings.glow;
    final t = _time;
    final eyeDir = cam.viewDirFrom(humanoid.root);
    var vi = 0;
    for (var i = 0; i < rings; i++) {
      final f = spine[i];
      final s = i / (n - 1);
      final r = SerpentRig.radiusAt(s);
      final frontier = form < 1 ? smoothstep(form - 0.08, form, s) : 0.0;
      for (var j = 0; j < m; j++) {
        final a = j / m * math.pi * 2;
        final nrm = f.normal * math.cos(a) + f.binormal * math.sin(a);
        final p = f.position + f.normal * (math.cos(a) * r * 0.85) + f.binormal * (math.sin(a) * r);
        final pr = proj(p);
        pos[vi * 2] = pr.x;
        pos[vi * 2 + 1] = pr.y;
        depth[vi] = pr.depth;
        final ndv = nrm.dot(eyeDir).abs();
        final fres = math.pow(1 - ndv, 2).toDouble();
        // Overlapping scale rows (offset every other row) + travelling shimmer.
        final u = s * 120, w = j / m * 14 + ((u.floor().isOdd) ? 0.5 : 0);
        final edge = math.max(_edge(u), _edge(w));
        final shimmer = 0.5 + 0.5 * math.sin(s * 40 - t * 3.2);
        final belly = 0.6 + 0.4 * (0.5 + 0.5 * math.cos(a));
        var k = (0.16 + 0.75 * fres + 0.55 * edge * (0.4 + 0.6 * shimmer)) * belly * glow;
        k *= 0.85 + 0.35 * _drive.audio + 0.4 * _drive.activation;
        k += frontier * 1.2;
        final c = mixArgb(prim, sec, fres);
        col[vi] = scaleRgb(c, (k * 0.62).clamp(0.0, 1.6).toDouble());
        vi++;
      }
    }
    final ringBase = vi;
    for (final hv in hf.vertices) {
      final pr = proj(hv.p);
      pos[vi * 2] = pr.x;
      pos[vi * 2 + 1] = pr.y;
      depth[vi] = pr.depth;
      final ndv = hv.n.dot(eyeDir).abs();
      final fres = math.pow(1 - ndv, 2).toDouble();
      final k = (0.22 + 0.8 * fres + hv.emissive) * glow * (0.9 + 0.4 * _drive.activation);
      col[vi] = scaleRgb(mixArgb(prim, sec, fres), (k * 0.6).clamp(0.0, 1.6).toDouble());
      vi++;
    }
    final backIdx = <int>[], frontIdx = <int>[];
    void tri(int a, int b, int c) {
      final d = (depth[a] + depth[b] + depth[c]) / 3;
      (d > centerDepth ? backIdx : frontIdx)..add(a)..add(b)..add(c);
    }

    for (var i = 0; i < rings - 1; i++) {
      for (var j = 0; j < m; j++) {
        final a = i * m + j, b = i * m + (j + 1) % m, c = (i + 1) * m + j, d = (i + 1) * m + (j + 1) % m;
        tri(a, c, b);
        tri(b, c, d);
      }
    }
    for (var k = 0; k < hf.indices.length; k += 3) {
      tri(ringBase + hf.indices[k], ringBase + hf.indices[k + 1], ringBase + hf.indices[k + 2]);
    }
    TriOp? mk(List<int> idx) =>
        idx.isEmpty ? null : TriOp(pos, col, Uint16List.fromList(idx), additive: true);
    return (back: mk(backIdx), front: mk(frontIdx));
  }

  static double _edge(double x) {
    final f = x - x.floorToDouble();
    final d = math.min(f, 1 - f);
    return 1 - smoothstep(0.0, 0.12, d);
  }

  TriOp? _humanoidMesh(({double x, double y, double depth, double scale}) Function(Vec3) proj, PerspectiveCamera cam) {
    final form = machine.humanoidFormation;
    if (form <= 0.001) return null;
    final reveal = HumanoidRig.revealHeight(form);
    final m = budget.sides;
    final verts = <_V>[];
    final idx = <int>[];
    for (final b in humanoid.bones) {
      final sides = b.name.startsWith('finger') ? 5 : m;
      _capsuleMesh(b, sides, verts, idx);
    }
    // Head (ellipsoid, visor-like helmet).
    _ellipsoid(humanoid.headCenter, humanoid.headForward, humanoid.headUp, const Vec3(0.115, 0.14, 0.12),
        m, verts, idx, material: 3);
    if (verts.length > 65000) return null;

    final eye = cam.viewDirFrom(humanoid.root);
    const light = Vec3(-0.45, 0.75, 0.55);
    final l = light.normalized();
    final prim = settings.primaryColor;
    final sec = settings.secondaryColor;
    final glow = settings.glow;
    final pos = Float32List(verts.length * 2);
    final col = Int32List(verts.length);
    final depth = Float64List(verts.length);
    for (var i = 0; i < verts.length; i++) {
      final v = verts[i];
      final pr = proj(v.p);
      pos[i * 2] = pr.x;
      pos[i * 2 + 1] = pr.y;
      depth[i] = pr.depth;
      final n = v.n;
      final ndl = math.max(0.0, n.dot(l));
      final refl = n * (2 * n.dot(l)) - l;
      final spec = math.pow(math.max(0.0, refl.dot(eye)), 22).toDouble();
      final ndv = math.max(0.0, n.dot(eye));
      final fres = math.pow(1 - ndv, 3).toDouble();
      // Overlapping armour scales: silver plates with dark gaps.
      final plate = (math.sin(v.along * 26) * math.sin(v.around * 9 + v.along * 6)) > -0.15;
      final seam = (math.sin(v.along * 13 + 0.6)).abs() < 0.09;
      double br, bg, bb;
      switch (v.material) {
        case 1: // under-suit
          br = 0.05; bg = 0.06; bb = 0.065;
        case 2: // hands
          br = 0.32; bg = 0.34; bb = 0.37;
        case 3: // helmet
          br = 0.42; bg = 0.45; bb = 0.5;
        default:
          if (plate) {
            br = 0.5; bg = 0.53; bb = 0.58;
          } else {
            br = 0.06; bg = 0.07; bb = 0.08;
          }
      }
      final lit = 0.16 + 0.84 * ndl;
      var r = br * lit + spec * 0.85;
      var g = bg * lit + spec * 0.9;
      var b = bb * lit + spec * 0.95;
      final rim = fres * 0.7 * glow;
      r += chR(prim) * rim;
      g += chG(prim) * rim;
      b += chB(prim) * rim;
      if (seam && v.material == 0) {
        final e = 0.75 * glow;
        r += chR(prim) * e;
        g += chG(prim) * e;
        b += chB(prim) * e;
      }
      // Energy-forging frontier while materialising.
      final fr = form < 1 ? smoothstep(reveal - 0.12, reveal, v.p.y) : 0.0;
      if (fr > 0) {
        r += chR(sec) * fr * 1.4;
        g += chG(sec) * fr * 1.4;
        b += chB(sec) * fr * 1.4;
      }
      col[i] = packArgb(r, g, b, 1);
    }
    // Keep triangles below the reveal plane, sorted back-to-front.
    final tris = <int>[];
    for (var k = 0; k < idx.length; k += 3) {
      final a = idx[k], b = idx[k + 1], c = idx[k + 2];
      if (form < 1 && math.min(verts[a].p.y, math.min(verts[b].p.y, verts[c].p.y)) > reveal) continue;
      tris.add(k);
    }
    tris.sort((x, y) {
      final dx = depth[idx[x]] + depth[idx[x + 1]] + depth[idx[x + 2]];
      final dy = depth[idx[y]] + depth[idx[y + 1]] + depth[idx[y + 2]];
      return dy.compareTo(dx);
    });
    final sorted = Uint16List(tris.length * 3);
    for (var i = 0; i < tris.length; i++) {
      sorted[i * 3] = idx[tris[i]];
      sorted[i * 3 + 1] = idx[tris[i] + 1];
      sorted[i * 3 + 2] = idx[tris[i] + 2];
    }
    if (sorted.isEmpty) return null;
    return TriOp(pos, col, sorted, additive: false);
  }

  void _capsuleMesh(Capsule c, int m, List<_V> verts, List<int> idx) {
    final axis = c.b - c.a;
    final len = axis.length;
    if (len < 1e-5) return;
    final t = axis * (1 / len);
    var u = t.cross(Vec3.forward);
    if (u.length < 0.2) u = t.cross(Vec3.right);
    u = u.normalized();
    final w = t.cross(u).normalized();
    // (position along axis, radius factor, normal tilt along axis)
    const rings = [(-0.2, 0.0, -1.0), (-0.12, 0.72, -0.6), (0.0, 1.0, 0.0), (0.5, 1.0, 0.0), (1.0, 1.0, 0.0),
      (1.12, 0.72, 0.6), (1.2, 0.0, 1.0)];
    final base = verts.length;
    for (final (along, rf, tilt) in rings) {
      final tt = along.clamp(0.0, 1.0).toDouble();
      final rad = lerpD(c.ra, c.rb, tt) * rf;
      final center = c.a + axis * along;
      // Caps extend by radius, not by axis length.
      final capShift = along < 0 ? t * (along / 0.2 * c.ra * 0.9 - axis.length * along)
          : (along > 1 ? t * ((along - 1) / 0.2 * c.rb * 0.9 - axis.length * (along - 1)) : Vec3.zero);
      for (var j = 0; j < m; j++) {
        final a = j / m * math.pi * 2;
        final radial = u * math.cos(a) + w * math.sin(a);
        final n = (radial * (1 - tilt.abs()) + t * tilt).normalized();
        verts.add(_V(center + capShift + radial * rad, n, along * len * 3 + center.y, a, c.material));
      }
    }
    for (var r = 0; r < rings.length - 1; r++) {
      for (var j = 0; j < m; j++) {
        final a = base + r * m + j, b = base + r * m + (j + 1) % m;
        final cc = base + (r + 1) * m + j, d = base + (r + 1) * m + (j + 1) % m;
        idx..add(a)..add(cc)..add(b)..add(b)..add(cc)..add(d);
      }
    }
  }

  void _ellipsoid(Vec3 c, Vec3 fwd, Vec3 up, Vec3 radii, int m, List<_V> verts, List<int> idx, {int material = 0}) {
    final side = up.cross(fwd).normalized();
    final lat = math.max(6, m ~/ 1.4);
    final base = verts.length;
    for (var i = 0; i <= lat; i++) {
      final th = i / lat * math.pi; // 0 top .. pi bottom
      for (var j = 0; j < m; j++) {
        final ph = j / m * math.pi * 2;
        final lx = math.sin(th) * math.cos(ph), ly = math.cos(th), lz = math.sin(th) * math.sin(ph);
        // Helmet: slightly pointed chin, flatter back.
        final chin = ly < 0 ? 1 - 0.25 * (-ly) * (lz > 0 ? 1 : 0.6) : 1.0;
        final p = c + side * (lx * radii.x * chin) + up * (ly * radii.y) + fwd * (lz * radii.z);
        final n = (side * (lx / radii.x) + up * (ly / radii.y) + fwd * (lz / radii.z)).normalized();
        verts.add(_V(p, n, p.y * 3, ph, material));
      }
    }
    for (var i = 0; i < lat; i++) {
      for (var j = 0; j < m; j++) {
        final a = base + i * m + j, b = base + i * m + (j + 1) % m;
        final cc = base + (i + 1) * m + j, d = base + (i + 1) * m + (j + 1) % m;
        idx..add(a)..add(cc)..add(b)..add(b)..add(cc)..add(d);
      }
    }
  }

  void _humanoidEmissive(RenderList out, ({double x, double y, double depth, double scale}) Function(Vec3) proj,
      List<int> pal) {
    final form = machine.humanoidFormation;
    if (form < 0.55) return;
    final g = settings.glow;
    final vis = smoothstep(0.55, 1.0, form);
    // Chest reactor.
    final pulse = 0.55 + 0.2 * math.sin(_time * 2.4) + 0.7 * _drive.activation + 0.5 * audio.level + 0.4 * audio.onset;
    final c = proj(humanoid.chestCore);
    final coreVis = smoothstep(0.62, 0.8, form);
    out.add(GlowOp(c.x, c.y, c.scale * (0.2 + 0.08 * pulse), scaleRgb(pal[0], 0.55 * pulse * g * coreVis), core: 0.7));
    out.add(GlowOp(c.x, c.y, c.scale * 0.055, scaleRgb(0xFFE8FFF6, 0.9 * coreVis), core: 1));
    // Energy orbs in the palms.
    for (final o in [humanoid.orbL, humanoid.orbR]) {
      final p = proj(o);
      final k = (0.45 + 0.25 * math.sin(_time * 3 + o.x) + 0.6 * _drive.activation + 0.3 * audio.level) * vis * g;
      out.add(GlowOp(p.x, p.y, p.scale * 0.17, scaleRgb(pal[1], 0.6 * k), core: 0.5));
      // Swirling orbit lines around each orb.
      final pts = <double>[];
      for (var i = 0; i <= 24; i++) {
        final a = _time * 3 + i / 24 * math.pi * 2;
        final q = proj(o + Vec3(math.cos(a) * 0.075, math.sin(a * 2) * 0.02, math.sin(a) * 0.075));
        pts..add(q.x)..add(q.y);
      }
      out.add(LineOp(Float32List.fromList(pts), scaleRgb(pal[0], 0.7 * k), 1.2));
    }
    // Eyes (visor) with blink.
    final h = humanoid;
    final side = h.headUp.cross(h.headForward).normalized();
    final eyeOpen = 1 - face.blink;
    for (final sgn in const [-1.0, 1.0]) {
      final e = proj(h.headCenter + h.headForward * 0.112 + h.headUp * (0.018 + face.gazeY * 0.004) +
          side * (0.042 * sgn + face.gazeX * 0.006));
      final k = (0.75 + 0.25 * math.sin(_time * 1.7) + 0.4 * _drive.listening) * vis * g * eyeOpen;
      if (k > 0.01) {
        out.add(GlowOp(e.x, e.y, e.scale * 0.03, scaleRgb(pal[1], 0.9 * k), core: 0.8));
        final l = proj(h.headCenter + h.headForward * 0.113 + h.headUp * 0.018 + side * (0.042 * sgn - 0.022));
        final r = proj(h.headCenter + h.headForward * 0.113 + h.headUp * 0.018 + side * (0.042 * sgn + 0.022));
        out.add(LineOp(Float32List.fromList([l.x, l.y, r.x, r.y]), scaleRgb(pal[1], 0.9 * k), 1.8 * eyeOpen + 0.2));
      }
    }
    // Mouth driven by FaceRig (viseme jaw + rounding + closed lips).
    final mouthC = h.headCenter + h.headForward * 0.098 - h.headUp * 0.068;
    final width = 0.034 * (1 - 0.45 * face.round);
    final open = 0.022 * face.jawOpen * (1 - face.lipsClosed);
    final pts = <double>[];
    for (var i = 0; i <= 16; i++) {
      final a = i / 16 * math.pi * 2;
      final q = proj(mouthC + side * (math.cos(a) * width) - h.headUp * (math.sin(a) * (open + 0.002)));
      pts..add(q.x)..add(q.y);
    }
    out.add(PolyOp(Float32List.fromList(pts), packArgb(0.01, 0.03, 0.03, vis)));
    out.add(LineOp(Float32List.fromList(pts), scaleRgb(pal[0], 0.55 * vis * g), 1.1));
  }

  void _serpentHeadFx(RenderList out, ({double x, double y, double depth, double scale}) Function(Vec3) proj,
      List<int> pal) {
    if (machine.serpentFormation < 0.97) return;
    final h = serpent.head;
    final side = h.up.cross(h.forward).normalized();
    final g = settings.glow;
    for (final sgn in const [-1.0, 1.0]) {
      final e = proj(h.position + h.forward * (0.15 + 0.01 * h.gazeX) + h.up * (0.05 + 0.005 * h.gazeY) + side * (0.058 * sgn));
      final k = h.eyeGlow * g; // serpents do not blink
      out.add(GlowOp(e.x, e.y, e.scale * 0.05, scaleRgb(pal[0], 0.85 * k), core: 0.9));
    }
    if (h.jaw > 0.15) {
      final m = proj(h.position + h.forward * 0.17 - h.up * 0.03);
      out.add(GlowOp(m.x, m.y, m.scale * 0.07 * h.jaw, scaleRgb(pal[1], 0.5 * h.jaw * g), core: 0.3));
    }
  }

  ({SpriteOp? back, SpriteOp? front}) _sprites(
      ({double x, double y, double depth, double scale}) Function(Vec3) proj, double centerDepth, List<int> pal) {
    final p = _particles;
    if (p.alive == 0) return (back: null, front: null);
    final bd = <double>[], bc = <int>[], fd = <double>[], fc = <int>[];
    for (var i = 0; i < p.alive; i++) {
      final pr = proj(Vec3(p.px[i], p.py[i], p.pz[i]));
      final lifeK = p.life[i] / p.maxLife[i];
      final fade = smoothstep(0, 0.15, lifeK) * (1 - smoothstep(0.6, 1, lifeK));
      final twinkle = p.kind[i] == 0 ? 0.45 + 0.55 * (0.5 + 0.5 * math.sin(p.life[i] * 9 + i)) : 1.0;
      final a = fade * twinkle;
      if (a < 0.03) continue;
      final size = p.size[i] * pr.scale * 0.0045 * (p.kind[i] == 2 ? 1.3 : 1.0);
      final col = scaleRgb(pal[_ci(p.colorIdx[i], 0, 3)], a * (p.kind[i] == 1 ? 1.2 : 0.9));
      if (pr.depth > centerDepth) {
        bd..add(pr.x)..add(pr.y)..add(size);
        bc.add(col);
      } else {
        fd..add(pr.x)..add(pr.y)..add(size);
        fc.add(col);
      }
    }
    SpriteOp? mk(List<double> d, List<int> c) =>
        c.isEmpty ? null : SpriteOp(Float32List.fromList(d), Int32List.fromList(c));
    return (back: mk(bd, bc), front: mk(fd, fc));
  }

  void _lightning(RenderList out, ({double x, double y, double depth, double scale}) Function(Vec3) proj,
      List<int> pal) {
    for (final b in _bolts) {
      final k = (1 - b.age / b.life) * settings.lightning;
      if (k <= 0) continue;
      final pts = Float32List(b.points.length * 2);
      for (var i = 0; i < b.points.length; i++) {
        final q = proj(b.points[i]);
        pts[i * 2] = q.x;
        pts[i * 2 + 1] = q.y;
      }
      if (budget.blur) out.add(LineOp(pts, scaleRgb(pal[1], 0.5 * k), 6, blur: 4));
      out.add(LineOp(pts, scaleRgb(0xFFE6FFFF, 0.95 * k), 1.4));
    }
  }

  /// Number of active lightning bolts (diagnostics / tests).
  int get boltCount => _bolts.length;
  int get particleCount => _particles.alive;
}

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

class _V {
  _V(this.p, this.n, this.along, this.around, this.material);
  final Vec3 p;
  final Vec3 n;
  final double along;
  final double around;
  final int material;
}

class _HeadVertex {
  const _HeadVertex(this.p, this.n, this.emissive);
  final Vec3 p;
  final Vec3 n;
  final double emissive;
}

/// Procedural cobra head: upper skull + hinged lower jaw + two fangs.
class _HeadMesh {
  _HeadMesh(this.vertices, this.indices);
  final List<_HeadVertex> vertices;
  final List<int> indices;

  static _HeadMesh build(SerpentHead h, int m, double visible) {
    final v = <_HeadVertex>[];
    final idx = <int>[];
    if (visible <= 0) return _HeadMesh(v, idx);
    final f = h.forward, u = h.up;
    final side = u.cross(f).normalized();
    final hinge = h.position + f * 0.01 - u * 0.012;
    final lat = math.max(5, m ~/ 2);

    void part(Vec3 center, Vec3 ff, Vec3 uu, double len, double wid, double hgt, double th0, double th1, double emissive) {
      final ss = uu.cross(ff).normalized();
      final base = v.length;
      for (var i = 0; i <= lat; i++) {
        final th = th0 + (th1 - th0) * i / lat;
        for (var j = 0; j < m; j++) {
          final ph = j / m * math.pi * 2;
          // x along forward in [-1,1]; snout tapers.
          final x = math.cos(ph);
          final rr = math.sin(ph);
          final taper = 1 - 0.5 * math.max(0.0, x);
          final y = math.cos(th) * hgt * taper, zz = math.sin(th) * rr * wid * taper;
          final p = center + ff * (x * len) + uu * y + ss * zz;
          final n = (ff * (x / len) + uu * (math.cos(th) / hgt) + ss * (math.sin(th) * rr / wid)).normalized();
          v.add(_HeadVertex(p, n, emissive));
        }
      }
      for (var i = 0; i < lat; i++) {
        for (var j = 0; j < m; j++) {
          final a = base + i * m + j, b = base + i * m + (j + 1) % m;
          final c = base + (i + 1) * m + j, d = base + (i + 1) * m + (j + 1) % m;
          idx..add(a)..add(c)..add(b)..add(b)..add(c)..add(d);
        }
      }
    }

    // Upper skull (top half) and lower jaw (bottom half, rotated open).
    part(hinge + f * 0.12, f, u, 0.13, 0.075, 0.055, 0.0, math.pi / 2, 0.0);
    final jawAngle = 0.75 * h.jaw;
    final axis = u.cross(f).normalized();
    final jf = f.rotate(axis, jawAngle);
    final ju = u.rotate(axis, jawAngle);
    part(hinge + jf * 0.11, jf, ju, 0.115, 0.065, 0.03, math.pi / 2, math.pi, 0.15);
    // Fangs (two thin triangles from the upper jaw tip).
    if (h.jaw > 0.12) {
      for (final s in const [-1.0, 1.0]) {
        final root = hinge + f * 0.205 + side * (0.028 * s) - u * 0.005;
        final tip = root - u * (0.045 * h.jaw) + f * 0.008;
        final w = side * 0.006;
        final base = v.length;
        v
          ..add(_HeadVertex(root - w, f, 0.9))
          ..add(_HeadVertex(root + w, f, 0.9))
          ..add(_HeadVertex(tip, f, 1.2));
        idx..add(base)..add(base + 1)..add(base + 2);
      }
    }
    return _HeadMesh(v, idx);
  }
}
