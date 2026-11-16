import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Purely local, original visual renderers. No WebViews, remote images, JS,
/// telemetry, network requests or separate AI sessions.
/// Command and microphone actions stay wired to the native JARVIS host.
class JarvisLocalVisual extends StatefulWidget {
  const JarvisLocalVisual({super.key, required this.apex});
  final bool apex;

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
    final color = widget.apex ? const Color(0xFFFFA52B) : const Color(0xFFB77DFF);
    return RepaintBoundary(
      child: Stack(children: [
        Positioned.fill(child: AnimatedBuilder(
          animation: _ticker,
          builder: (_, __) => CustomPaint(
            painter: _CorePainter(_ticker.value * math.pi * 2, widget.apex),
            isComplex: true,
            willChange: true,
          ),
        )),
        Positioned(
          top: 14,
          left: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.apex ? 'APEX • REACTOR' : 'MIRA • NEURAL FIELD',
              style: TextStyle(color: color, fontSize: 13,
                fontWeight: FontWeight.w700, letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('LOCAL VISUAL • JARVIS NATIVE ENGINE',
              style: TextStyle(color: Colors.white60,
                fontSize: 10, letterSpacing: 1.2)),
          ]),
        ),
        const Positioned(
          bottom: 12, left: 0, right: 0,
          child: Text('Animation only · AI and microphone remain in JARVIS',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 10)),
        ),
      ]),
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
    canvas.drawRect(Offset.zero & size,
      Paint()..shader = const RadialGradient(
        colors: [Color(0xFF081B27), Color(0xFF020509), Color(0xFF000000)],
        stops: [0, .48, 1],
      ).createShader(Offset.zero & size));

    if (apex) {
      _apex(canvas, center, radius);
    } else {
      _mira(canvas, center, radius);
    }
  }

  void _glow(Canvas c, Offset at, double r, Color color, double strength) {
    final base = color.withValues(alpha: (strength * .75).clamp(0.0, 1.0));
    c.drawCircle(at, r,
      Paint()..shader = RadialGradient(
        colors: [base, color.withValues(alpha: strength * .14),
                 color.withValues(alpha: 0)],
        stops: const [0, .34, 1],
      ).createShader(Rect.fromCircle(center: at, radius: r)));
  }

  void _ring(Canvas c, Offset p, double r, Color color,
      {double width = 1, double alpha = 1}) {
    c.drawCircle(p, r, Paint()
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true);
  }

  void _arc(Canvas c, Offset p, double r, double start,
      double length, Color color, double width, double alpha) {
    final rect = Rect.fromCircle(center: p, radius: r);
    c.drawArc(rect, start, length, false,
      Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..isAntiAlias = true);
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
      _ring(c, p, rr, layer.isEven ? amber : cyan,
        width: layer == 2 ? 1.8 : .8, alpha: .16 + .11 * (layer % 3));
      final count = 17 + layer * 6;
      for (var k = 0; k < count; k++) {
        final a = tau * k / count + angle;
        final seg = .022 + .035 * ((k * 7 + layer * 11) % 5) / 4;
        _arc(c, p, rr, a, seg, layer.isEven ? gold : amber,
          layer == 3 ? 2.1 : 1.05, .35 + .5 * ((k * 13 + layer) % 7) / 7);
        if (k % 4 == 0) {
          final pos = p + Offset(math.cos(a), math.sin(a)) * rr;
          c.drawCircle(pos, .9 + (k % 3) * .4,
            Paint()..color = (k % 3 == 0 ? cyan : gold)
              .withValues(alpha: .6));
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
      c.drawLine(start, end,
        Paint()..color = (i % 9 == 0 ? cyan : amber)
          .withValues(alpha: i % 3 == 0 ? .55 : .13)
          ..strokeWidth = i % 9 == 0 ? 1.3 : .7);
    }
    for (var i = 0; i < 95; i++) {
      final a = i * 2.399963 + phase * (i.isEven ? .30 : -.24);
      final rr = r * (.18 + .83 * ((i * 37 % 97) / 97));
      final pos = p + Offset(math.cos(a), math.sin(a)) * rr;
      final power = .42 + .58 * math.sin(phase * 1.5 + i * .65).abs();
      c.drawCircle(pos, (i % 11 == 0 ? 1.8 : 1) * power,
        Paint()..color = (i % 4 == 0 ? cyan : gold)
          .withValues(alpha: .2 + .7 * power));
    }
    _ring(c, p, r * .17, gold, width: 2.2, alpha: .9);
    _ring(c, p, r * .115, cyan, width: 1.1, alpha: .8);
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
        final y = math.sin(a + tilt) * rad * (.34 + .58 * math.sin(ribbon * .35).abs());
        final rotated = Offset(
          x * math.cos(tilt) - y * math.sin(tilt),
          x * math.sin(tilt) + y * math.cos(tilt));
        final at = p + rotated;
        if (k == 0) { path.moveTo(at.dx, at.dy); }
        else { path.lineTo(at.dx, at.dy); }
      }
      c.drawPath(path, Paint()
        ..color = (ribbon % 3 == 0 ? aqua : (ribbon.isEven ? violet : magenta))
          .withValues(alpha: .14 + .37 * (ribbon % 5) / 5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ribbon % 7 == 0 ? 1.5 : .8);
    }
    for (var i = 0; i < 190; i++) {
      final angle = i * 2.399963 + phase * (.09 + (i % 4) * .045);
      final dis = r * math.sqrt(((i * 73) % 197) / 197);
      final z = .4 + .6 * math.sin(i * .47 + phase * 1.75).abs();
      final x = math.cos(angle) * dis;
      final y = math.sin(angle) * dis * (.75 + .24 * math.cos(phase * .5));
      final pos = p + Offset(x, y);
      final color = i % 4 == 0 ? aqua : i % 3 == 0 ? magenta : violet;
      c.drawCircle(pos, .45 + (i % 9 == 0 ? 1.6 : .75) * z,
        Paint()..color = color.withValues(alpha: .23 + .72 * z));
      if (i % 17 == 0) _glow(c, pos, 7 + 4 * z, color, .30);
    }
    _ring(c, p, r * .16, aqua, width: 1.4, alpha: .47 + .43 * pulse);
  }

  @override
  bool shouldRepaint(covariant _CorePainter old) =>
      old.phase != phase || old.apex != apex;
}
