import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Offline, first-party visual-only HUDs: no external pages, tracking, network,
/// microphone or app permissions. Task/voice commands live in native JARVIS.
enum OfflineHudStyle { apex, mira }

class OfflineJarvisHud extends StatefulWidget {
  const OfflineJarvisHud({super.key, required this.style});
  final OfflineHudStyle style;
  @override
  State<OfflineJarvisHud> createState() => _OfflineJarvisHudState();
}

class _OfflineJarvisHudState extends State<OfflineJarvisHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this, duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apex = widget.style == OfflineHudStyle.apex;
    final primary = apex ? const Color(0xFFFFAD34) : const Color(0xFFBB67FF);
    return Stack(children: [
      Positioned.fill(child: RepaintBoundary(
        child: CustomPaint(painter: _OfflineHudPainter(
          time: _clock, apex: apex,
        )),
      )),
      Positioned(left: 16, top: 18, child: Text(
        apex ? 'APEX  //  OFFLINE REACTOR' : 'MIRA  //  OFFLINE NEURAL FIELD',
        style: TextStyle(fontSize: 12, color: primary,
            letterSpacing: 1.6, fontWeight: FontWeight.w600),
      )),
      const Positioned(right: 16, top: 18, child: Text(
        'LOCAL VISUAL · NO WEBVIEW',
        style: TextStyle(color: Colors.white54, fontSize: 9),
      )),
      Positioned(left: 0, right: 0, bottom: 18, child: Text(
        apex ? 'REACTOR STABLE' : 'NEURAL FIELD STABLE',
        textAlign: TextAlign.center,
        style: TextStyle(color: primary.withValues(alpha: .75),
            fontSize: 11, letterSpacing: 2.5),
      )),
    ]);
  }
}

class _OfflineHudPainter extends CustomPainter {
  _OfflineHudPainter({required Animation<double> time, required this.apex})
      : super(repaint: time), clock = time;
  final Animation<double> clock;
  final bool apex;
  static const amber = Color(0xFFFFA821);
  static const blue = Color(0xFF20F5FF);
  static const violet = Color(0xFFB55AFF);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value * math.pi * 2;
    final center = Offset(size.width / 2, size.height * .50);
    final radius = math.min(size.width * .40, size.height * .33);
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF020409));
    if (radius < 8) return;
    if (apex) {
      _apex(canvas, center, radius, t);
    } else {
      _mira(canvas, center, radius, t);
    }
  }

  void _ring(Canvas c, Offset center, double rx, double ry, double angle,
      Color color, {double width = 1, double opacity = .8}) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2,
      height: ry * 2), Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    c.restore();
  }

  void _spark(Canvas c, Offset p, double r, Color col, double opacity) {
    final glow = Paint()..shader = RadialGradient(colors: [
      col.withValues(alpha: opacity),
      col.withValues(alpha: 0),
    ]).createShader(Rect.fromCircle(center: p, radius: r * 5));
    c.drawCircle(p, r * 5, glow);
    c.drawCircle(p, r * .52, Paint()..color = Colors.white.withValues(alpha: opacity));
  }

  void _apex(Canvas c, Offset o, double r, double t) {
    c.drawCircle(o, r * 1.24, Paint()..shader = RadialGradient(colors: [
      amber.withValues(alpha: .22), amber.withValues(alpha: .065),
      Colors.transparent,
    ]).createShader(Rect.fromCircle(center: o, radius: r * 1.24)));
    for (var layer = 0; layer < 8; layer++) {
      final rad = r * (.24 + layer * .109);
      final count = 28 + layer * 11;
      for (var i = 0; i < count; i++) {
        final a = (i / count * math.pi * 2) +
          (layer.isEven ? t * .23 : -t * .14);
        final p = Paint()
          ..color = (layer.isEven ? amber : blue).withValues(
            alpha: (.28 + .45 * (math.sin(i * 1.93 + t * 3).abs())))
          ..style = PaintingStyle.stroke
          ..strokeWidth = layer % 3 == 0 ? 2.2 : 1.05;
        c.drawArc(Rect.fromCircle(center: o, radius: rad), a,
          math.pi * 2 / count * .58, false, p);
      }
    }
    for (var i = 0; i < 4; i++) {
      _ring(c, o, r * (.88 + i * .055), r * (.20 + i * .075),
          t * (.07 + i * .026) + i * .8,
          i.isEven ? blue : amber, width: 1.5, opacity: .55);
    }
    for (var i = 0; i < 140; i++) {
      final a = i * 2.39996 + t * (i.isEven ? .08 : -.11);
      final radial = r * (.13 + ((i * 37) % 101) / 101 * 1.05);
      final point = Offset(o.dx + math.cos(a) * radial,
        o.dy + math.sin(a) * radial);
      _spark(c, point, .5 + (i % 4) * .18,
          i % 5 == 0 ? blue : amber, .30 + .65 * math.sin(t * 2 + i).abs());
    }
    _core(c, o, r * .19, amber, blue, t);
  }

  void _mira(Canvas c, Offset o, double r, double t) {
    c.drawCircle(o, r * 1.3, Paint()..shader = RadialGradient(colors: [
      violet.withValues(alpha: .26),
      blue.withValues(alpha: .10), Colors.transparent,
    ]).createShader(Rect.fromCircle(center: o, radius: r * 1.3)));
    for (var strand = 0; strand < 42; strand++) {
      final start = strand / 42 * math.pi * 2;
      final path = Path();
      for (var step = 0; step <= 70; step++) {
        final p = step / 70;
        final orbit = r * (.15 + p * .93);
        final theta = start + p * 2.8 + t * .14 +
            math.sin(p * 8 + t + strand * .5) * .16;
        final q = Offset(o.dx + math.cos(theta) * orbit,
          o.dy + math.sin(theta) * orbit * (.76 + .18 * math.cos(t)));
        if (step == 0) { path.moveTo(q.dx, q.dy); }
        else { path.lineTo(q.dx, q.dy); }
      }
      c.drawPath(path, Paint()
        ..color = (strand % 3 == 0 ? blue : violet)
            .withValues(alpha: .24 + .23 * math.sin(t + strand).abs())
        ..strokeWidth = strand % 7 == 0 ? 1.7 : .8
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3));
    }
    for (var i = 0; i < 170; i++) {
      final a = i * 2.39996 + t * .15;
      final rr = r * math.sqrt((i + 1) / 170);
      _spark(c, Offset(o.dx + math.cos(a) * rr,
          o.dy + math.sin(a) * rr * .87),
        .6 + (i % 6) * .18, i % 3 == 0 ? blue : violet,
        .22 + .72 * math.sin(i * .82 - t * 2).abs());
    }
    for (var i = 0; i < 3; i++) {
      _ring(c, o, r * (.70 + i * .16), r * (.46 + i * .12),
          t * .12 + i * .5, i.isEven ? violet : blue,
          width: 1.1, opacity: .35);
    }
    _core(c, o, r * .16, violet, blue, t);
  }

  void _core(Canvas c, Offset o, double r, Color a, Color b, double t) {
    final pulse = 1 + .08 * math.sin(t * 3);
    c.drawCircle(o, r * 2.9 * pulse, Paint()..shader = RadialGradient(colors: [
      Colors.white.withValues(alpha: .83),
      a.withValues(alpha: .84),
      b.withValues(alpha: .27),
      Colors.transparent,
    ], stops: const [0, .12, .40, 1]).createShader(
      Rect.fromCircle(center: o, radius: r * 2.9 * pulse)));
    c.drawCircle(o, r * .28, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _OfflineHudPainter oldDelegate) =>
      oldDelegate.apex != apex;
}
