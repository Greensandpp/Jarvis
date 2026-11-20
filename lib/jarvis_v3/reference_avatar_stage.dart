import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../avatar/avatar_perf.dart';
import 'assistant_activity.dart';
import 'neon_theme.dart';

/// An approved character render plus the points the live effects attach to,
/// in the image's own pixel coordinates.
@immutable
class AvatarReference {
  const AvatarReference({
    required this.id,
    required this.asset,
    required this.size,
    required this.eyes,
    required this.core,
    required this.portal,
    required this.portalRadius,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    this.extraGlows = const [],
    this.serpentTrail = false,
  });

  final String id;
  final String asset;
  final Size size;
  final List<Offset> eyes;
  final Offset core;
  final Offset portal;
  final double portalRadius;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  /// Other emitters (palm orbs, the serpent's eye).
  final List<Offset> extraGlows;

  /// Draw the coiling energy serpent trail around the figure.
  final bool serpentTrail;

  /// The original user-approved JARVIS metallic hologram (assets, Nov 3).
  static const jarvis = AvatarReference(
    id: 'jarvis-gold',
    asset: 'assets/images/jarvis_male_hologram_gold.png',
    size: Size(896, 1200),
    eyes: [Offset(379, 318), Offset(512, 318)],
    core: Offset(448, 712),
    portal: Offset(448, 1040),
    portalRadius: 270,
    primary: NeonColors.amber,
    secondary: NeonColors.gold,
    tertiary: Color(0xFFFF8A1C),
  );

  /// The owner-supplied Serpent Guardian reference (Nov 20).
  static const serpent = AvatarReference(
    id: 'serpent-guardian',
    asset: 'assets/images/serpent_guardian.jpg',
    size: Size(941, 1672),
    eyes: [Offset(452, 197), Offset(490, 197)],
    core: Offset(511, 325),
    portal: Offset(470, 1468),
    portalRadius: 400,
    primary: Color(0xFF2BFFA3),
    secondary: NeonColors.cyan,
    tertiary: Color(0xFFB36BFF),
    extraGlows: [Offset(118, 522), Offset(832, 560), Offset(786, 140)],
    serpentTrail: true,
  );
}

/// Introduction stages, in order.
enum IntroStage { particles, convergence, assembly, ignition, stabilise, done }

IntroStage introStageAt(double t) {
  if (t < 0.22) return IntroStage.particles;
  if (t < 0.45) return IntroStage.convergence;
  if (t < 0.72) return IntroStage.assembly;
  if (t < 0.86) return IntroStage.ignition;
  if (t < 1.0) return IntroStage.stabilise;
  return IntroStage.done;
}

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Fullscreen cinematic stage: the approved render, breathing and lit by an
/// effects layer that follows the real [activity]. No manual state input.
class ReferenceAvatarStage extends StatefulWidget {
  const ReferenceAvatarStage({
    super.key,
    required this.reference,
    required this.activity,
    required this.soundLevel,
    this.playIntro = false,
    this.reduceMotion = false,
    this.onIntroFinished,
    this.quality = 1.0,
  });

  final AvatarReference reference;
  final ValueListenable<AssistantActivity> activity;

  /// 0..1 microphone or speech level, read every frame.
  final double Function() soundLevel;
  final bool playIntro;
  final bool reduceMotion;
  final VoidCallback? onIntroFinished;

  /// 0.5..1 particle density (adaptive quality).
  final double quality;

  @override
  State<ReferenceAvatarStage> createState() => ReferenceAvatarStageState();
}

class ReferenceAvatarStageState extends State<ReferenceAvatarStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _loop;
  late final AnimationController _intro;
  double _level = 0;
  bool _foreground = true;

  /// Frame pacing monitor: logs `SERPENT_PERF` / `JARVIS_PERF` lines (adb
  /// logcat) and lowers particle density when the device cannot keep up.
  late final AvatarPerfMonitor perf;
  late double _quality = widget.quality;
  double get quality => _quality;
  final Stopwatch _sinceAdapt = Stopwatch()..start();

  IntroStage get introStage => _intro.isAnimating || _intro.value < 1
      ? introStageAt(_intro.value)
      : IntroStage.done;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    perf = AvatarPerfMonitor(
        tag: widget.reference == AvatarReference.serpent ? 'SERPENT_PERF' : 'JARVIS_PERF')
      ..attach();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..addListener(_tick);
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onIntroFinished?.call();
    });
    if (widget.playIntro && !widget.reduceMotion) {
      _intro.forward();
    } else {
      _intro.value = 1;
    }
    _syncLoop();
  }

  void _tick() {
    final target = widget.soundLevel().clamp(0.0, 1.0);
    _level += (target - _level) * 0.25;
    final elapsed = _loop.lastElapsedDuration;
    if (elapsed != null) perf.onTick(elapsed);
    perf.onFrameBuilt(Duration.zero, 0, (70 * _quality).round());
    // Adaptive quality: thin the particles if frames run late for 5 s.
    if (_sinceAdapt.elapsed > const Duration(seconds: 5)) {
      _sinceAdapt.reset();
      final fps = perf.snapshot().fps;
      if (fps > 0 && fps < 45 && _quality > 0.5) {
        _quality = (_quality - 0.2).clamp(0.5, 1.0);
      }
    }
  }

  void _syncLoop() {
    final run = _foreground && !widget.reduceMotion;
    if (run && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!run && _loop.isAnimating) {
      _loop.stop();
    }
  }

  /// Skip Intro.
  void skipIntro() {
    if (_intro.value < 1) {
      _intro.value = 1;
      widget.onIntroFinished?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No animation work while the app is not visible.
    _foreground = state == AppLifecycleState.resumed;
    _syncLoop();
  }

  @override
  void didUpdateWidget(covariant ReferenceAvatarStage old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion != old.reduceMotion) {
      if (widget.reduceMotion) skipIntro();
      _syncLoop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    perf.detach();
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.reference;
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, c) {
          final box = Size(c.maxWidth, c.maxHeight);
          // Keep the figure clear of the header and lift it above the chat
          // and dock, so the conversation never sits on the face or chest.
          final area = Rect.fromLTRB(
            0,
            box.height * 0.07,
            box.width,
            box.height * 0.86,
          );
          final fitted = applyBoxFit(BoxFit.contain, ref.size, area.size);
          final dst = const Alignment(
            0,
            -0.6,
          ).inscribe(fitted.destination, area);
          final scale = dst.width / ref.size.width;
          return AnimatedBuilder(
            animation: Listenable.merge([_loop, _intro, widget.activity]),
            builder: (context, _) {
              final activity = widget.activity.value;
              final t = _loop.value * 12; // seconds
              final intro = _intro.value;
              final assemble = _seg(intro, 0.42, 0.74);
              final breathe = widget.reduceMotion
                  ? 0.0
                  : math.sin(t * 2 * math.pi / 4.2);
              final speakPulse = activity == AssistantActivity.speaking
                  ? _level
                  : 0.0;
              final s = 1 + 0.008 * breathe + 0.012 * speakPulse;
              final sway = widget.reduceMotion
                  ? 0.0
                  : math.sin(t * 2 * math.pi / 9) * 0.012;
              final dim = activity == AssistantActivity.disconnected
                  ? 0.55
                  : 1.0;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: NeonColors.background),
                  CustomPaint(
                    painter: _BackdropPainter(
                      ref,
                      dst,
                      scale,
                      t,
                      intro,
                      activity,
                      _quality,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: dst,
                    child: Opacity(
                      opacity: (assemble * dim).clamp(0.0, 1.0),
                      child: ClipRect(
                        clipper: _AssembleClipper(assemble),
                        child: Transform(
                          alignment: Alignment.bottomCenter,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateY(sway)
                            ..scaleByDouble(s, s, 1, 1)
                            ..translateByDouble(0, -3 * breathe, 0, 1),
                          child: ShaderMask(
                            // Feather the render's edges into the black scene.
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (r) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0, 0.07, 0.9, 1],
                            ).createShader(r),
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (r) => const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.white,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                                stops: [0, 0.06, 0.94, 1],
                              ).createShader(r),
                              child: Image.asset(
                                ref.asset,
                                key: ValueKey('avatar-${ref.id}'),
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                                gaplessPlayback: true,
                                semanticLabel: ref == AvatarReference.serpent
                                    ? 'Serpent Guardian'
                                    : 'JARVIS humanoid',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _EffectsPainter(
                        ref,
                        dst,
                        scale,
                        t,
                        intro,
                        activity,
                        _level,
                        _quality,
                        widget.reduceMotion,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AssembleClipper extends CustomClipper<Rect> {
  _AssembleClipper(this.p);
  final double p;
  @override
  Rect getClip(Size size) {
    // The form builds upward from the portal.
    final top = size.height * (1 - p);
    return Rect.fromLTRB(0, top, size.width, size.height);
  }

  @override
  bool shouldReclip(_AssembleClipper old) => old.p != p;
}

Color _activityTint(AvatarReference ref, AssistantActivity a) => switch (a) {
  AssistantActivity.listening => NeonColors.cyan,
  AssistantActivity.thinking || AssistantActivity.processing => ref.secondary,
  AssistantActivity.executing => ref.tertiary,
  AssistantActivity.error => NeonColors.error,
  AssistantActivity.disconnected => const Color(0xFF6B6B6B),
  _ => ref.primary,
};

/// Deterministic pseudo-random so particles do not jump between frames.
double _rand(int i, int salt) {
  final x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(
    this.ref,
    this.dst,
    this.scale,
    this.t,
    this.intro,
    this.activity,
    this.quality,
  );
  final AvatarReference ref;
  final Rect dst;
  final double scale;
  final double t;
  final double intro;
  final AssistantActivity activity;
  final double quality;

  @override
  void paint(Canvas canvas, Size size) {
    final tint = _activityTint(ref, activity);
    // Ambient glow behind the figure.
    final c = dst.topLeft + ref.core * scale;
    canvas.drawCircle(
      c,
      size.shortestSide * 0.7,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                tint.withValues(alpha: 0.16 * _seg(intro, 0.3, 0.9)),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: c, radius: size.shortestSide * 0.7),
            ),
    );
    // Floor reflection band under the portal.
    final p = dst.topLeft + ref.portal * scale;
    final floor = Rect.fromCenter(
      center: p.translate(0, 30 * scale),
      width: size.width * 1.2,
      height: 160 * scale,
    );
    canvas.drawOval(
      floor,
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(floor),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter o) => true;
}

class _EffectsPainter extends CustomPainter {
  _EffectsPainter(
    this.ref,
    this.dst,
    this.scale,
    this.t,
    this.intro,
    this.activity,
    this.level,
    this.quality,
    this.reduceMotion,
  );
  final AvatarReference ref;
  final Rect dst;
  final double scale;
  final double t;
  final double intro;
  final AssistantActivity activity;
  final double level;
  final double quality;
  final bool reduceMotion;

  Offset _p(Offset o) => dst.topLeft + o * scale;

  @override
  void paint(Canvas canvas, Size size) {
    final tint = _activityTint(ref, activity);
    final glowPaint = Paint()..blendMode = BlendMode.plus;
    final portal = _p(ref.portal);
    final core = _p(ref.core);

    // 1. Energy particles appear, 2. converge into the form.
    final particles = (70 * quality).round();
    final appear = _seg(intro, 0.0, 0.22);
    final converge = _seg(intro, 0.22, 0.6);
    final thinking =
        activity == AssistantActivity.thinking ||
        activity == AssistantActivity.processing;
    for (var i = 0; i < particles; i++) {
      final a = _rand(i, 1) * 2 * math.pi;
      final r0 = (0.25 + 0.7 * _rand(i, 2)) * size.shortestSide * 0.75;
      final speed = 0.04 + 0.08 * _rand(i, 3);
      final phase = (t * speed + _rand(i, 4)) % 1.0;
      Offset pos;
      if (converge < 1) {
        // Scattered sparks drifting toward the figure's core.
        final r = r0 * (1 - 0.85 * Curves.easeIn.transform(converge));
        pos = core + Offset(math.cos(a + t * 0.3), math.sin(a + t * 0.3)) * r;
      } else if (thinking) {
        // THINKING: energy converges on the core.
        final r = r0 * (1 - phase) * 0.8;
        pos = core + Offset(math.cos(a), math.sin(a)) * r;
      } else {
        // IDLE and others: calm plasma rising from the portal.
        final spread = ref.portalRadius * scale * (0.2 + 0.8 * _rand(i, 5));
        final x = portal.dx + math.cos(a) * spread;
        final rise = phase * dst.height * 0.75;
        pos = Offset(x + math.sin(t + i) * 6, portal.dy - rise);
      }
      final alpha =
          appear *
          (converge < 1 ? 1.0 : (1 - phase)) *
          (0.35 + 0.65 * _rand(i, 6));
      final rad =
          (0.8 + 1.8 * _rand(i, 7)) *
          (activity == AssistantActivity.speaking ? 1 + level : 1);
      final col = i % 5 == 0
          ? ref.tertiary
          : (i % 2 == 0 ? ref.secondary : tint);
      glowPaint
        ..color = col.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
      canvas.drawCircle(pos, rad, glowPaint);
    }

    // Plasma trails converging (intro) / serpent energy coil (serpent mode).
    final trails = _seg(intro, 0.18, 0.55) * (1 - _seg(intro, 0.62, 0.8));
    if (trails > 0) _drawConvergingTrails(canvas, core, size, trails, tint);
    if (ref.serpentTrail) _drawSerpentCoil(canvas, tint, _seg(intro, 0.6, 1.0));

    // 5. Energy rings stabilise at the portal.
    final rings = _seg(intro, 0.78, 1.0);
    if (rings > 0) {
      final spin = activity == AssistantActivity.executing ? 1.6 : 0.25;
      for (var k = 0; k < 3; k++) {
        final rr =
            ref.portalRadius *
            scale *
            (0.55 + 0.22 * k) *
            (0.85 + 0.15 * rings);
        final rect = Rect.fromCenter(
          center: portal,
          width: rr * 2,
          height: rr * 0.42,
        );
        final start = t * spin * (k.isEven ? 1 : -1) + k;
        canvas.drawArc(
          rect,
          start,
          math.pi * (1.1 + 0.3 * k),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..blendMode = BlendMode.plus
            ..color = (k == 1 ? ref.secondary : tint).withValues(
              alpha: 0.55 * rings,
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
      }
      if (activity == AssistantActivity.listening) {
        // Audio-reactive ripple from the real microphone level.
        final rr = ref.portalRadius * scale * (1.05 + 0.35 * level);
        canvas.drawOval(
          Rect.fromCenter(center: portal, width: rr * 2, height: rr * 0.42),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 + 4 * level
            ..color = NeonColors.cyan.withValues(alpha: 0.35 + 0.5 * level)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }

    // 4. Eyes and core illuminate; they pulse with breathing and speech.
    final ignite = _seg(intro, 0.72, 0.86);
    if (ignite > 0) {
      final breath = reduceMotion
          ? 0.5
          : 0.5 + 0.5 * math.sin(t * 2 * math.pi / 4.2);
      final voice = activity == AssistantActivity.speaking ? level : 0.0;
      final eyeR = 14 * scale * (1 + 0.6 * voice) + 4;
      for (final e in ref.eyes) {
        _glow(
          canvas,
          _p(e),
          eyeR,
          tint,
          ignite * (0.55 + 0.25 * breath + 0.4 * voice),
        );
      }
      final coreR = 60 * scale * (1 + 0.5 * voice + 0.1 * breath) + 6;
      _glow(
        canvas,
        core,
        coreR,
        tint,
        ignite * (0.45 + 0.3 * breath + 0.5 * voice),
      );
      for (final g in ref.extraGlows) {
        _glow(
          canvas,
          _p(g),
          40 * scale + 4,
          ref.primary,
          ignite * (0.4 + 0.3 * breath),
        );
      }
    }
  }

  void _glow(Canvas canvas, Offset c, double r, Color col, double a) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: (0.8 * a).clamp(0.0, 1.0)),
            col.withValues(alpha: (0.6 * a).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          stops: const [0, 0.25, 1],
        ).createShader(rect),
    );
  }

  void _drawConvergingTrails(
    Canvas canvas,
    Offset core,
    Size size,
    double a,
    Color tint,
  ) {
    for (var k = 0; k < 4; k++) {
      final path = Path();
      final ang0 = k * math.pi / 2 + t * 0.6;
      for (var j = 0; j <= 40; j++) {
        final u = j / 40;
        final r =
            size.shortestSide *
            0.6 *
            (1 - u) *
            (1 - 0.5 * _seg(intro, 0.2, 0.55));
        final ang = ang0 + u * 3.2;
        final pt = core + Offset(math.cos(ang), math.sin(ang) * 1.3) * r;
        j == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..blendMode = BlendMode.plus
          ..color = (k.isEven ? tint : ref.tertiary).withValues(alpha: 0.6 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  /// A luminous helix that coils up the figure, mirroring the trails in the
  /// reference render; its phase drifts so the coil appears to wind.
  void _drawSerpentCoil(Canvas canvas, Color tint, double a) {
    if (a <= 0) return;
    final top = dst.top + dst.height * 0.18;
    final bottom = dst.top + dst.height * 0.86;
    final cx = dst.center.dx;
    final w = dst.width * 0.36;
    final path = Path();
    final drift = reduceMotion ? 0.0 : t * 0.9;
    for (var j = 0; j <= 120; j++) {
      final u = j / 120;
      final y = bottom - (bottom - top) * u;
      final x =
          cx + math.sin(u * math.pi * 5 + drift) * w * (0.6 + 0.4 * (1 - u));
      j == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    for (final (width, alpha) in [(7.0, 0.18), (2.2, 0.55)]) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [ref.primary, tint, ref.tertiary],
          ).createShader(dst)
          ..color = Colors.white.withValues(alpha: alpha * a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width),
      );
    }
  }

  @override
  bool shouldRepaint(_EffectsPainter o) => true;
}
