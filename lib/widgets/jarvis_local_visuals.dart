import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Purely local, original visual renderers. No WebViews, remote images, JS,
/// telemetry, network requests or separate AI sessions.
/// Command and microphone actions stay wired to the native JARVIS host.
class JarvisLocalVisual extends StatefulWidget {
  const JarvisLocalVisual({
    super.key,
    required this.apex,
    this.minimalist = false,
  });
  final bool apex;
  final bool minimalist;

  @override
  State<JarvisLocalVisual> createState() => _JarvisLocalVisualState();
}

class _JarvisLocalVisualState extends State<JarvisLocalVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.apex
        ? const Color(0xFFFFA52B)
        : const Color(0xFFB77DFF);
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ticker,
              builder: (_, __) => CustomPaint(
                painter: _CorePainter(_ticker.value * math.pi * 2, widget.apex),
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
          if (!widget.minimalist)
            Positioned(
              top: 14,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.apex ? 'APEX • REACTOR' : 'MIRA • NEURAL FIELD',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'LOCAL VISUAL • JARVIS NATIVE ENGINE',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          if (!widget.minimalist)
            const Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Text(
                'Animation only · AI and microphone remain in JARVIS',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _CorePainter extends CustomPainter {
  _CorePainter(this.phase, this.apex);
  final double phase;
  final bool apex;

  static const tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.50);
    final radius = math.min(size.width * 0.44, size.height * 0.32);
    if (radius <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF081B27), Color(0xFF020509), Color(0xFF000000)],
          stops: [0, .48, 1],
        ).createShader(Offset.zero & size),
    );

    if (apex) {
      _apex(canvas, center, radius);
    } else {
      _mira(canvas, center, radius);
    }
  }

  void _glow(Canvas c, Offset at, double r, Color color, double strength) {
    final base = color.withValues(alpha: (strength * .75).clamp(0.0, 1.0));
    c.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            base,
            color.withValues(alpha: strength * .14),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .34, 1],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
  }

  void _ring(
    Canvas c,
    Offset p,
    double r,
    Color color, {
    double width = 1,
    double alpha = 1,
  }) {
    c.drawCircle(
      p,
      r,
      Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..isAntiAlias = true,
    );
  }

  void _arc(
    Canvas c,
    Offset p,
    double r,
    double start,
    double length,
    Color color,
    double width,
    double alpha,
  ) {
    final rect = Rect.fromCircle(center: p, radius: r);
    c.drawArc(
      rect,
      start,
      length,
      false,
      Paint()
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..isAntiAlias = true,
    );
  }

  void _apex(Canvas c, Offset p, double r) {
    const amber = Color(0xFFFFA128);
    const gold = Color(0xFFFFDD8B);
    const cyan = Color(0xFF23EEFF);
    final pulse = .5 + .5 * math.sin(phase * 2.0);
    _glow(c, p, r * .88, amber, .55 + pulse * .14);
    _glow(c, p, r * .35, gold, .88);
    _glow(c, p, r * .14, const Color(0xFFFFFFFF), .88);

    for (var layer = 0; layer < 7; layer++) {
      final rr = r * (.25 + layer * .103);
      final direction = layer.isEven ? 1.0 : -1.0;
      final angle = phase * direction * (.45 + layer * .075);
      _ring(
        c,
        p,
        rr,
        layer.isEven ? amber : cyan,
        width: layer == 2 ? 1.8 : .8,
        alpha: .16 + .11 * (layer % 3),
      );
      final count = 17 + layer * 6;
      for (var k = 0; k < count; k++) {
        final a = tau * k / count + angle;
        final seg = .022 + .035 * ((k * 7 + layer * 11) % 5) / 4;
        _arc(
          c,
          p,
          rr,
          a,
          seg,
          layer.isEven ? gold : amber,
          layer == 3 ? 2.1 : 1.05,
          .35 + .5 * ((k * 13 + layer) % 7) / 7,
        );
        if (k % 4 == 0) {
          final pos = p + Offset(math.cos(a), math.sin(a)) * rr;
          c.drawCircle(
            pos,
            .9 + (k % 3) * .4,
            Paint()..color = (k % 3 == 0 ? cyan : gold).withValues(alpha: .6),
          );
        }
      }
    }
    // Structural radial microcircuit tracks, different from generic orbits.
    for (var i = 0; i < 132; i++) {
      final a = tau * i / 132 - phase * .06;
      final inner = r * (.33 + (i % 5) * .04);
      final outer = r * (.77 + (i % 8) * .017);
      final start = p + Offset(math.cos(a), math.sin(a)) * inner;
      final end = p + Offset(math.cos(a), math.sin(a)) * outer;
      c.drawLine(
        start,
        end,
        Paint()
          ..color = (i % 9 == 0 ? cyan : amber).withValues(
            alpha: i % 3 == 0 ? .55 : .13,
          )
          ..strokeWidth = i % 9 == 0 ? 1.3 : .7,
      );
    }
    for (var i = 0; i < 95; i++) {
      final a = i * 2.399963 + phase * (i.isEven ? .30 : -.24);
      final rr = r * (.18 + .83 * ((i * 37 % 97) / 97));
      final pos = p + Offset(math.cos(a), math.sin(a)) * rr;
      final power = .42 + .58 * math.sin(phase * 1.5 + i * .65).abs();
      c.drawCircle(
        pos,
        (i % 11 == 0 ? 1.8 : 1) * power,
        Paint()
          ..color = (i % 4 == 0 ? cyan : gold).withValues(
            alpha: .2 + .7 * power,
          ),
      );
    }
    _ring(c, p, r * .17, gold, width: 2.2, alpha: .9);
    _ring(c, p, r * .115, cyan, width: 1.1, alpha: .8);
    _apexCinematic(c, p, r);
  }

  void _mira(Canvas c, Offset p, double r) {
    const violet = Color(0xFFAF7AFF);
    const magenta = Color(0xFFFF59D6);
    const aqua = Color(0xFF38EFFF);
    final pulse = .5 + .5 * math.sin(phase * 2);
    _glow(c, p, r, violet, .45 + pulse * .14);
    _glow(c, p, r * .47, magenta, .46);
    _glow(c, p, r * .23, aqua, .75);
    // Organic ribbons across multiple elliptical planes.
    for (var ribbon = 0; ribbon < 24; ribbon++) {
      final path = Path();
      final rad = r * (.25 + ribbon * .031);
      final tilt = phase * (ribbon.isEven ? .22 : -.14) + ribbon * .21;
      for (var k = 0; k <= 80; k++) {
        final a = tau * k / 80;
        final w = .60 + .40 * math.sin(a * 3 + phase + ribbon * .31);
        final x = math.cos(a + tilt) * rad * w;
        final y =
            math.sin(a + tilt) *
            rad *
            (.34 + .58 * math.sin(ribbon * .35).abs());
        final rotated = Offset(
          x * math.cos(tilt) - y * math.sin(tilt),
          x * math.sin(tilt) + y * math.cos(tilt),
        );
        final at = p + rotated;
        if (k == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      c.drawPath(
        path,
        Paint()
          ..color =
              (ribbon % 3 == 0 ? aqua : (ribbon.isEven ? violet : magenta))
                  .withValues(alpha: .14 + .37 * (ribbon % 5) / 5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ribbon % 7 == 0 ? 1.5 : .8,
      );
    }
    for (var i = 0; i < 190; i++) {
      final angle = i * 2.399963 + phase * (.09 + (i % 4) * .045);
      final dis = r * math.sqrt(((i * 73) % 197) / 197);
      final z = .4 + .6 * math.sin(i * .47 + phase * 1.75).abs();
      final x = math.cos(angle) * dis;
      final y = math.sin(angle) * dis * (.75 + .24 * math.cos(phase * .5));
      final pos = p + Offset(x, y);
      final color = i % 4 == 0
          ? aqua
          : i % 3 == 0
          ? magenta
          : violet;
      c.drawCircle(
        pos,
        .45 + (i % 9 == 0 ? 1.6 : .75) * z,
        Paint()..color = color.withValues(alpha: .23 + .72 * z),
      );
      if (i % 17 == 0) _glow(c, pos, 7 + 4 * z, color, .30);
    }
    _ring(c, p, r * .16, aqua, width: 1.4, alpha: .47 + .43 * pulse);
    _miraHumanoid(c, p, r, violet, magenta, aqua, pulse);
  }

  /// Procedural holographic female bust (no external assets): silhouette,
  /// facial contour lines, scanlines, a sampled point cloud and eye glints,
  /// breathing slightly with the animation phase.
  void _miraHumanoid(
    Canvas c,
    Offset p,
    double r,
    Color violet,
    Color magenta,
    Color aqua,
    double pulse,
  ) {
    final breathe = 1 + .012 * math.sin(phase * 1.3);
    final s = r * 1.05 * breathe;
    final top = p.translate(0, -s * .62);
    Offset q(double x, double y) => top + Offset(x * s, y * s);
    final body = Path()
      // head (slightly oval), hair volume, neck, shoulders and chest
      ..moveTo(q(0, 0).dx, q(0, 0).dy)
      ..cubicTo(
        q(.17, 0).dx,
        q(.17, 0).dy,
        q(.21, .14).dx,
        q(.21, .14).dy,
        q(.2, .25).dx,
        q(.2, .25).dy,
      )
      ..cubicTo(
        q(.2, .36).dx,
        q(.2, .36).dy,
        q(.15, .45).dx,
        q(.15, .45).dy,
        q(.08, .5).dx,
        q(.08, .5).dy,
      )
      ..lineTo(q(.075, .6).dx, q(.075, .6).dy)
      ..cubicTo(
        q(.16, .66).dx,
        q(.16, .66).dy,
        q(.42, .68).dx,
        q(.42, .68).dy,
        q(.5, .82).dx,
        q(.5, .82).dy,
      )
      ..lineTo(q(.56, 1.12).dx, q(.56, 1.12).dy)
      ..lineTo(q(-.56, 1.12).dx, q(-.56, 1.12).dy)
      ..lineTo(q(-.5, .82).dx, q(-.5, .82).dy)
      ..cubicTo(
        q(-.42, .68).dx,
        q(-.42, .68).dy,
        q(-.16, .66).dx,
        q(-.16, .66).dy,
        q(-.075, .6).dx,
        q(-.075, .6).dy,
      )
      ..lineTo(q(-.08, .5).dx, q(-.08, .5).dy)
      ..cubicTo(
        q(-.15, .45).dx,
        q(-.15, .45).dy,
        q(-.2, .36).dx,
        q(-.2, .36).dy,
        q(-.2, .25).dx,
        q(-.2, .25).dy,
      )
      ..cubicTo(
        q(-.21, .14).dx,
        q(-.21, .14).dy,
        q(-.17, 0).dx,
        q(-.17, 0).dy,
        q(0, 0).dx,
        q(0, 0).dy,
      )
      ..close();
    final bounds = body.getBounds();
    // translucent volume
    c.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            aqua.withValues(alpha: .20 + .08 * pulse),
            violet.withValues(alpha: .10),
            magenta.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    // scanlines moving upward, clipped to the figure
    c.save();
    c.clipPath(body);
    final step = s * .022;
    final offset = (phase * s * .05) % step;
    for (var y = bounds.bottom + offset; y > bounds.top; y -= step) {
      c.drawLine(
        Offset(bounds.left, y),
        Offset(bounds.right, y),
        Paint()
          ..color = aqua.withValues(alpha: .10)
          ..strokeWidth = .7,
      );
    }
    // facial contour (latitude) lines on the head
    for (var k = 1; k < 7; k++) {
      final cy = q(0, .04 + k * .065).dy;
      final w = s * (.2 - .012 * (k - 3).abs() * (k - 3).abs() * .6);
      c.drawOval(
        Rect.fromCenter(
          center: Offset(top.dx, cy),
          width: w * 2,
          height: s * .02,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = violet.withValues(alpha: .35),
      );
    }
    // vertical meridians on the torso
    for (var k = -4; k <= 4; k++) {
      final x = top.dx + k * s * .11;
      c.drawLine(
        Offset(x, q(0, .72).dy),
        Offset(x * .98 + top.dx * .02, bounds.bottom),
        Paint()
          ..color = magenta.withValues(alpha: .12)
          ..strokeWidth = .6,
      );
    }
    c.restore();
    // point cloud sampled inside the silhouette (deterministic)
    for (var i = 0; i < 520; i++) {
      final fx = ((i * 7919) % 1000) / 1000, fy = ((i * 104729) % 997) / 997;
      final pt = Offset(
        bounds.left + fx * bounds.width,
        bounds.top + fy * bounds.height,
      );
      if (!body.contains(pt)) continue;
      final tw = .35 + .65 * math.sin(phase * 2.2 + i * .37).abs();
      c.drawCircle(
        pt,
        .6 + .7 * tw,
        Paint()
          ..color = (i % 5 == 0 ? magenta : aqua).withValues(
            alpha: .18 + .5 * tw,
          ),
      );
    }
    // outline with glow
    c.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = aqua.withValues(alpha: .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    c.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = aqua.withValues(alpha: .75),
    );
    // eyes + a soft "voice" glow at the lips
    for (final ex in [-.075, .075]) {
      _glow(c, q(ex, .23), s * .03, aqua, .9);
    }
    _glow(c, q(0, .38), s * (.025 + .02 * pulse), magenta, .55 + .3 * pulse);
    // emitter pedestal
    final ped = Rect.fromCenter(
      center: q(0, 1.14),
      width: s * 1.3,
      height: s * .12,
    );
    c.drawOval(
      ped,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = violet.withValues(alpha: .7),
    );
    _glow(c, ped.center, s * .45, violet, .35 + .2 * pulse);
  }

  /// APEX cinematic layer: perspective-tilted orbit rings and a light sweep.
  void _apexCinematic(Canvas c, Offset p, double r) {
    const gold = Color(0xFFFFDD8B), cyan = Color(0xFF23EEFF);
    for (var k = 0; k < 3; k++) {
      final tilt = .28 + k * .2;
      final spin = phase * (k.isEven ? .7 : -.5) + k;
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(spin * .15 + k * 1.05);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r * (2.05 + k * .2),
        height: r * (2.05 + k * .2) * tilt,
      );
      c.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = (k == 1 ? cyan : gold).withValues(alpha: .45),
      );
      // a bright "satellite" travelling on the orbit
      final a = phase * (1.2 + k * .4);
      final sat = Offset(
        math.cos(a) * rect.width / 2,
        math.sin(a) * rect.height / 2,
      );
      _glow(c, sat, r * .07, k == 1 ? cyan : gold, .9);
      c.restore();
    }
    // radar-like light sweep
    final sweep = phase * 1.4;
    c.drawCircle(
      p,
      r * 1.05,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweep,
          endAngle: sweep + 1.1,
          colors: [
            gold.withValues(alpha: 0),
            gold.withValues(alpha: .22),
            gold.withValues(alpha: 0),
          ],
          transform: GradientRotation(sweep),
        ).createShader(Rect.fromCircle(center: p, radius: r * 1.05)),
    );
    // anamorphic lens flare
    c.drawRect(
      Rect.fromCenter(center: p, width: r * 2.6, height: 2.2),
      Paint()
        ..shader = LinearGradient(
          colors: [
            cyan.withValues(alpha: 0),
            Colors.white.withValues(alpha: .55),
            cyan.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCenter(center: p, width: r * 2.6, height: 2.2)),
    );
  }

  @override
  bool shouldRepaint(covariant _CorePainter old) =>
      old.phase != phase || old.apex != apex;
}
