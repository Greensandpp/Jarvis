import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'avatar_engine.dart';
import 'avatar_settings.dart';

/// True procedural 3D geometry, projected and depth-sorted on Flutter Canvas.
/// CPU mesh prototype, NOT a rigged production asset or GPU particle engine.
class ProceduralAvatarView extends StatefulWidget {
  const ProceduralAvatarView({
    super.key,
    required this.model,
    required this.style,
    this.state = AvatarState.idle,
    this.audioLevel,
    this.visemes = const [],
    this.audioPosition,
    this.closing = false,
  });
  final AvatarModel model;
  final AvatarStyle style;
  final AvatarState state;
  final double? Function()? audioLevel;
  final Duration Function()? audioPosition;
  final List<VisemeCue> visemes;
  final bool closing;
  @override
  State<ProceduralAvatarView> createState() => ProceduralAvatarViewState();
}

class ProceduralAvatarViewState extends State<ProceduralAvatarView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  late final AvatarTimeline timeline;
  final AudioFaceDriver face = AudioFaceDriver();
  final ValueNotifier<int> repaint = ValueNotifier(0);
  Duration? _last;
  Duration _lastPaint = Duration.zero;
  FaceFrame _face = const FaceFrame();
  int paintedFrames = 0;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    timeline = AvatarTimeline(intro: widget.style.intro)..request(widget.state);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    if (widget.style.audio && widget.style.intro)
      SystemSound.play(SystemSoundType.click);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    timeline.paused = !TickerMode.of(context) || !_foreground;
    if (!timeline.paused && !_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
    if (timeline.paused && _ticker.isActive) _ticker.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    timeline.paused = !_foreground || !TickerMode.of(context);
    _last = null;
    if (timeline.paused) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant ProceduralAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    timeline.request(widget.state);
    if (widget.closing && !oldWidget.closing) {
      if (widget.style.outro) {
        timeline.close();
      } else {
        timeline.closed = true;
      }
      if (widget.style.audio && widget.style.outro)
        SystemSound.play(SystemSoundType.click);
    }
    if (!widget.closing && oldWidget.closing) timeline.restart();
  }

  void _tick(Duration elapsed) {
    final dt = _last == null
        ? 0.0
        : ((elapsed - _last!).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = elapsed;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    timeline.tick(dt * widget.style.speed * (reduce ? .25 : 1));
    _face = face.sample(
      dt: dt,
      speaking: widget.state == AvatarState.speaking,
      rms: widget.audioLevel?.call(),
      position: widget.audioPosition?.call() ?? Duration.zero,
      cues: widget.visemes,
    );
    final fps = reduce
        ? 15
        : switch (widget.style.profile) {
            GraphicsProfile.lite => 24,
            GraphicsProfile.balanced => 30,
            GraphicsProfile.ultra => 60,
          };
    if (elapsed < _lastPaint ||
        (elapsed - _lastPaint).inMicroseconds >= 1000000 / fps) {
      _lastPaint = elapsed;
      paintedFrames++;
      repaint.value++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: CustomPaint(
        key: const ValueKey('procedural-avatar'),
        painter: AvatarMeshPainter(
          model: widget.model,
          style: widget.style,
          timeline: timeline,
          face: () => _face,
          repaint: repaint,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _Face {
  _Face(this.points, this.color, this.emissive);
  final List<V3> points;
  final Color color;
  final bool emissive;
  double get depth => points.fold(0.0, (v, p) => v + p.z) / points.length;
}

class AvatarMeshPainter extends CustomPainter {
  AvatarMeshPainter({
    required this.model,
    required this.style,
    required this.timeline,
    required this.face,
    super.repaint,
  });
  final AvatarModel model;
  final AvatarStyle style;
  final AvatarTimeline timeline;
  final FaceFrame Function() face;
  static const tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = style, t = timeline.time;
    final dynamics = AvatarDynamics(timeline.state, t);
    canvas.drawRect(Offset.zero & size, Paint()..color = s.background);
    if (timeline.closed) return;
    final formation = timeline.state == AvatarState.intro
        ? timeline.progress * .1
        : timeline.progress;
    final scale = math.min(size.width / 2.6, size.height / 3.8) * s.scale;
    final center = Offset(
      size.width * (.5 + s.x * .6),
      size.height * (.5 + s.y * .6),
    );
    final yaw = math.sin(t * .3) * .12;
    V3 transform(V3 p) => V3(
      p.x * math.cos(yaw) - p.z * math.sin(yaw),
      p.y,
      p.z * math.cos(yaw) + p.x * math.sin(yaw),
    );
    Offset project(V3 p) {
      final q = transform(p);
      final perspective = 4.8 / (4.8 - q.z);
      return center +
          Offset(q.x * scale * perspective, q.y * scale * perspective);
    }

    void glow(V3 p, double radius, Color c, double strength) {
      final point = project(p), r = radius * scale;
      canvas.drawCircle(
        point,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              c.withValues(alpha: (strength * .7).clamp(0, 1)),
              c.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: point, radius: r)),
      );
    }

    glow(const V3(0, 0, -.5), 1.7, s.primary, .2);
    final faces = <_Face>[];
    void sphere(
      V3 p,
      V3 radius,
      Color color, {
      bool emissive = false,
      int? sections,
    }) {
      final n = sections ?? (s.profile == GraphicsProfile.ultra ? 12 : 8),
          rings = s.profile == GraphicsProfile.lite ? 4 : 6;
      V3 v(int i, int j) {
        final a = i * math.pi / rings, b = j * tau / n;
        final spread = (1 - formation) * math.sin((i * n + j) * 1.7 + t) * .55;
        return p +
            V3(
              math.sin(a) * math.cos(b) * radius.x + spread,
              math.cos(a) * radius.y + (1 - formation) * 1.5,
              math.sin(a) * math.sin(b) * radius.z,
            );
      }

      for (var i = 0; i < rings; i++) {
        for (var j = 0; j < n; j++) {
          faces.add(
            _Face(
              [v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1)],
              color,
              emissive,
            ),
          );
        }
      }
    }

    void limb(V3 a, V3 b, double radius, Color color) {
      final tangent = (b - a).unit;
      final u = tangent.cross(const V3(0, 0, 1)).unit,
          v = tangent.cross(u).unit;
      const n = 8;
      for (var j = 0; j < n; j++) {
        V3 ring(V3 p, int k) =>
            p +
            (u * math.cos(k * tau / n) + v * math.sin(k * tau / n)) * radius;
        faces.add(
          _Face(
            [ring(a, j), ring(b, j), ring(b, j + 1), ring(a, j + 1)],
            color,
            false,
          ),
        );
      }
    }

    final breath = math.sin(t * 1.8 * dynamics.energy) * .018;
    final hover = math.sin(t * .8) * .035;
    final armor = Color.lerp(const Color(0xFF122732), s.primary, .18)!;
    final trim = Color.lerp(const Color(0xFF8C947B), s.secondary, .3)!;
    // Independently articulated body parts with real z coordinates.
    sphere(V3(0, -.44 + hover, 0), V3(.36 + breath, .48, .21), armor);
    sphere(V3(0, .05 + hover, 0), const V3(.23, .25, .15), trim);
    sphere(V3(0, .25 + hover, 0), const V3(.28, .19, .18), armor);
    final headTurn = dynamics.headTilt;
    sphere(V3(headTurn, -1.10 + hover, .01), const V3(.20, .26, .18), armor);
    final ff = face();
    sphere(
      V3(headTurn, -.98 + hover + ff.jaw * s.lipSync * .07, .09),
      const V3(.14, .07, .12),
      trim,
    );
    for (final side in [-1.0, 1.0]) {
      final shoulder = V3(side * .43, -.65 + hover, 0);
      final elbow = V3(
        side * .60,
        -.20 + hover,
        .06 + math.sin(t + side) * .03,
      );
      final hand = V3(side * .84, -.08 + hover + dynamics.handLift, .20);
      sphere(shoulder, const V3(.19, .19, .20), trim);
      limb(shoulder, elbow, .105, armor);
      sphere(elbow, const V3(.115, .115, .12), trim);
      limb(elbow, hand, .085, armor);
      sphere(hand, const V3(.10, .055, .13), trim);
      for (var f = 0; f < 5; f++) {
        final start = hand + V3((f - 2) * .035, .0, .08);
        final curl = math.sin(t * 1.2 + f * .4) * .018;
        final joint = start + V3(side * .035, -.015 - curl, .07);
        limb(start, joint, .014, armor);
        limb(joint, joint + V3(0, -.025 - curl, .035), .012, trim);
      }
      final knee = V3(side * .18, .84 + hover, .02),
          foot = V3(side * .15, 1.43 + hover, .10);
      limb(V3(side * .16, .32 + hover, 0), knee, .12, armor);
      sphere(knee, const V3(.12, .13, .13), trim);
      limb(knee, foot, .082, armor);
      sphere(foot, const V3(.09, .08, .17), trim);
      sphere(
        V3(side * .073 + headTurn, -1.13 + hover, .172),
        V3(.057, .018 * dynamics.eyeOpen, .018),
        s.secondary,
        emissive: true,
      );
    }
    sphere(
      V3(0, -.49 + hover, .218),
      V3(.095 + breath, .095 + breath, .036),
      s.primary,
      emissive: true,
    );
    // A separate spline tube, hood, eyes and jaw for the holographic cobra.
    if (model == AvatarModel.serpent) {
      final spline = SerpentSpline(t);
      final count = s.profile == GraphicsProfile.lite ? 32 : 56;
      final length = (timeline.state == AvatarState.formation
          ? formation
          : 1.0);
      for (var i = 0; i < count; i++) {
        if (i / count > length) continue;
        final a = spline.at(i / count) + V3(0, hover, 0),
            b = spline.at((i + 1) / count) + V3(0, hover, 0);
        limb(
          a,
          b,
          .055 + i / count * .012,
          Color.lerp(s.primary, s.secondary, i / count)!,
        );
        if (i % 2 == 0)
          sphere(
            a,
            const V3(.058, .025, .058),
            s.secondary,
            emissive: true,
            sections: 6,
          );
      }
      final h = spline.at(1) + V3(0, hover, 0);
      if (length > .9) {
        sphere(
          h + const V3(-.05, .13, -.04),
          const V3(.23, .28, .045),
          s.secondary,
        );
        sphere(h, const V3(.18, .105, .12), s.primary);
        sphere(
          h + V3(.05, .075 + (.5 + .5 * math.sin(t * 1.4)) * .04, .05),
          const V3(.13, .035, .09),
          s.secondary,
        );
        for (final side in [-1.0, 1.0]) {
          sphere(
            h + V3(side * .10, -.035, .09),
            const V3(.024, .025, .02),
            const Color(0xFFB5FF63),
            emissive: true,
          );
        }
      }
    }
    // Geometry variants are concepts, not a claim that final meshes exist.
    if (model == AvatarModel.angelic) {
      for (final side in [-1.0, 1.0]) {
        for (var feather = 0; feather < 7; feather++) {
          limb(
            V3(side * .28, -.6, -.16),
            V3(
              side * (.65 + feather * .065),
              -1.25 + feather * .16 + math.sin(t) * .04,
              -.30,
            ),
            .035,
            s.secondary,
          );
        }
      }
    }
    if (model == AvatarModel.crystal) {
      for (var i = 0; i < 5; i++)
        sphere(
          V3((i - 2) * .09, -1.36 - (2 - (i - 2).abs()) * .04, 0),
          const V3(.035, .16, .05),
          s.secondary,
          sections: 4,
        );
    }
    for (var i = 0; i < 3; i++) {
      final a = t * .3 * s.outerMotion * dynamics.orbitSpeed + i * tau / 3;
      sphere(
        V3(math.cos(a) * .95, -.5 + math.sin(a * 1.3) * .6, math.sin(a) * .6),
        const V3(.045, .09, .045),
        s.secondary,
        emissive: true,
        sections: 4,
      );
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final light = const V3(-.4, -.5, 1).unit;
    for (final f in faces) {
      final p = f.points;
      final normal = (p[1] - p[0]).cross(p[2] - p[0]).unit;
      final shade = f.emissive ? 1.0 : (.35 + normal.dot(light).abs() * .65);
      final base = f.color;
      final c = Color.fromRGBO(
        (base.r * 255 * shade).round(),
        (base.g * 255 * shade).round(),
        (base.b * 255 * shade).round(),
        formation.clamp(0, 1),
      );
      final path = Path();
      for (var i = 0; i < p.length; i++) {
        final q = project(p[i]);
        if (i == 0) {
          path.moveTo(q.dx, q.dy);
        } else {
          path.lineTo(q.dx, q.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = c);
      if (f.emissive)
        canvas.drawPath(
          path,
          Paint()
            ..color = s.secondary.withValues(alpha: .4 * formation)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5,
        );
    }
    glow(
      V3(0, -.49 + hover, .25),
      .30,
      s.primary,
      .8 * formation * dynamics.energy,
    );
    // Holographic rings and multicolor energy ribbons in real 3D space.
    for (var ring = 0; ring < 3; ring++) {
      final path = Path();
      for (var i = 0; i <= 100; i++) {
        final a = i * tau / 100 + t * .3 * s.outerMotion + ring * .6;
        final v = V3(
          math.cos(a) * (.85 + ring * .08),
          1.56 + math.sin(a) * .12,
          math.sin(a) * .5,
        );
        final q = project(v);
        if (i == 0) {
          path.moveTo(q.dx, q.dy);
        } else {
          path.lineTo(q.dx, q.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.secondary.withValues(alpha: .5 * formation)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final particleCount =
        ((s.profile == GraphicsProfile.lite
                    ? 50
                    : s.profile == GraphicsProfile.ultra
                    ? 240
                    : 110) *
                s.density)
            .round();
    for (var i = 0; i < particleCount; i++) {
      final angle = i * 2.399 + t * .2 * s.outerMotion;
      final y = ((i * .071 + t * .08 * s.backgroundMotion) % 3.3) - 1.65;
      final r = .6 + (i % 7) * .07;
      final p = V3(math.cos(angle) * r, y, math.sin(angle) * r * .55);
      final at = project(p);
      final shimmer = (.5 + .5 * math.sin(t * 5 + i)) * s.glitter;
      canvas.drawCircle(
        at,
        (.5 + shimmer) * s.particleSize,
        Paint()
          ..color = s.particles.withValues(
            alpha: (.35 + shimmer * .6) * formation,
          ),
      );
    }
    for (var ribbon = 0; ribbon < 3; ribbon++) {
      for (var i = 0; i < 80; i++) {
        final a = i * .11 + t * .5 * s.outerMotion + ribbon * 2.1;
        V3 v(double a, double i) =>
            V3(math.cos(a) * .78, 1.5 - i * .038, math.sin(a) * .65);
        canvas.drawLine(
          project(v(a, i.toDouble())),
          project(v(a + .11, i + 1.0)),
          Paint()
            ..color = Color.lerp(
              s.primary,
              [
                s.secondary,
                const Color(0xFFFFC657),
                const Color(0xFFEF79FF),
              ][ribbon],
              i / 80,
            )!.withValues(alpha: .65 * formation)
            ..strokeWidth = 1.4,
        );
      }
    }
    final flash =
        (math.sin(t * (1 + s.lightningFrequency * 4) * tau) > .97 &&
        s.lightningFrequency > 0);
    if (flash && timeline.state != AvatarState.closing) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final p = project(
          V3(-.8 + i * .17, math.sin(i * 3.1 + t) * .13 - .2, .7),
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.lightning
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AvatarMeshPainter oldDelegate) => true;
}
