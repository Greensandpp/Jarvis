// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'aira_models.dart';

/// Mutable per-frame values written by the AIRA view's ticker and read by the
/// painter. Kept in one object so painting allocates as little as possible.
class AiraFrame extends ChangeNotifier {
  double t = 0; // animated phase (seconds, already speed-scaled)
  double clock = 0; // wall-clock seconds since start
  double energy = .62;
  double spread = 1;
  double warmth = 0;
  double sound = 0; // 0..1 microphone / speech level
  double yaw = 0;
  double pitch = 0;
  double stateAge = 99; // seconds since visual state changed
  double tapAge = 99; // seconds since the last tap burst
  double detail = 1; // 0.25..1 particle budget
  double brightness = 1;
  AiraVisualState state = AiraVisualState.idle;

  void tick() => notifyListeners();
}

const _tau = math.pi * 2;

/// Deterministic hash in 0..1. Stable particle identity without allocations.
double _h(int i, int salt) {
  var x = (i * 374761393 + salt * 668265263 + 0x5bd1e995) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  x = x ^ (x >> 16);
  return (x & 0xffff) / 65535.0;
}

double _frac(double v) => v - v.floorToDouble();

/// Scratch 3D → 2D projector (perspective, yaw then pitch).
class _Proj {
  double cx = 0, cy = 0, r = 1, cyw = 1, syw = 0, cp = 1, sp = 0;
  double x = 0, y = 0, depth = .5, scale = 1;
  static const fov = 3.2;

  void setup(Offset c, double radius, double yaw, double pitch) {
    cx = c.dx;
    cy = c.dy;
    r = radius;
    cyw = math.cos(yaw);
    syw = math.sin(yaw);
    cp = math.cos(pitch);
    sp = math.sin(pitch);
  }

  void p(double px, double py, double pz) {
    final x1 = px * cyw + pz * syw;
    final z1 = -px * syw + pz * cyw;
    final y2 = py * cp - z1 * sp;
    final z2 = py * sp + z1 * cp;
    scale = fov / (fov - z2);
    x = cx + x1 * r * scale;
    y = cy + y2 * r * scale;
    depth = ((z2 + 1.2) / 2.4).clamp(0.0, 1.0);
  }
}

/// Batched additive points: 3 colours × 3 alpha levels × 3 sizes.
class _Dots {
  _Dots() {
    for (var i = 0; i < 27; i++) {
      _buf.add(Float32List(_cap * 2));
      _n.add(0);
    }
  }
  static const _cap = 2400;
  final List<Float32List> _buf = [];
  final List<int> _n = [];
  final Paint _paint = Paint()
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  void add(double x, double y, int color, double alpha, double size) {
    final a = alpha < .33 ? 0 : (alpha < .66 ? 1 : 2);
    final s = size < 1.6 ? 0 : (size < 3.0 ? 1 : 2);
    final b = color * 9 + a * 3 + s;
    final n = _n[b];
    if (n >= _cap) return;
    _buf[b][n * 2] = x;
    _buf[b][n * 2 + 1] = y;
    _n[b] = n + 1;
  }

  void flush(Canvas canvas, List<Color> palette, double gain, double unit,
      {bool halo = true}) {
    const alphas = [.28, .58, .95];
    const sizes = [1.25, 2.3, 3.7];
    for (var b = 0; b < 27; b++) {
      final n = _n[b];
      if (n == 0) continue;
      final color = palette[b ~/ 9];
      final a = alphas[(b ~/ 3) % 3];
      final s = sizes[b % 3];
      final pts = Float32List.sublistView(_buf[b], 0, n * 2);
      if (halo) {
        _paint
          ..color = color.withValues(alpha: (a * gain * .2).clamp(0.0, 1.0))
          ..strokeWidth = s * unit * 3.6;
        canvas.drawRawPoints(ui.PointMode.points, pts, _paint);
      }
      _paint
        ..color = Color.lerp(color, const Color(0xFFFFFFFF), a > .9 ? .35 : 0)!
            .withValues(alpha: (a * gain).clamp(0.0, 1.0))
        ..strokeWidth = s * unit;
      canvas.drawRawPoints(ui.PointMode.points, pts, _paint);
      _n[b] = 0;
    }
  }
}

class AiraCorePainter extends CustomPainter {
  AiraCorePainter({required this.model, required this.frame, this.compact = false})
      : super(repaint: frame);

  final AiraModel model;
  final AiraFrame frame;
  final bool compact;

  final _Proj _pr = _Proj();
  final _Dots _dots = _Dots();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus
    ..isAntiAlias = true;
  final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.plus
    ..isAntiAlias = true;

  late List<Color> _pal; // primary, secondary, accent
  late double _gain;
  late double _u; // device-independent stroke unit

  /// Exposed for tests: last frame threw and fallback was drawn.
  bool lastPaintFailed = false;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final f = frame;
    final r = math.min(size.width, size.height * .82) * (compact ? .40 : .35);
    final c = Offset(size.width / 2, size.height * (compact ? .5 : .47));
    _u = compact ? .8 : (r / 140).clamp(.8, 1.8);
    _gain = ((.72 + .48 * f.energy) * f.brightness).clamp(.35, 1.8);
    final warm = f.warmth;
    Color tint(Color col) => warm >= 0
        ? Color.lerp(col, const Color(0xFFFFC46B), warm * .22)!
        : Color.lerp(col, const Color(0xFFB07BFF), -warm * .25)!;
    _pal = [tint(model.primary), tint(model.secondary), tint(model.accent)];
    try {
      canvas.save();
      _bloom(canvas, c, r);
      switch (model) {
        case AiraModel.neuralReactor:
          _neuralReactor(canvas, c, r);
        case AiraModel.amberHologram:
          _amberHologram(canvas, c, r);
        case AiraModel.electricWeb:
          _electricWeb(canvas, c, r);
        case AiraModel.aiHead:
          _aiHead(canvas, c, r);
        case AiraModel.jellyfish:
          _jellyfish(canvas, c, r);
        case AiraModel.violetVortex:
          _violetVortex(canvas, c, r);
        case AiraModel.auroraRibbon:
          _auroraRibbon(canvas, c, r);
        case AiraModel.dnaHelix:
          _dnaHelix(canvas, c, r);
        case AiraModel.crystalBloom:
          _crystalBloom(canvas, c, r);
        case AiraModel.solarFlare:
          _solarFlare(canvas, c, r);
      }
      _stateOverlay(canvas, c, r);
      _glitter(canvas, c, r);
      _dots.flush(canvas, _pal, _gain, _u, halo: !compact || frame.detail > .5);
      canvas.restore();
      lastPaintFailed = false;
    } catch (_) {
      canvas.restore();
      lastPaintFailed = true;
      _dots.flush(canvas, _pal, 0, 0, halo: false); // discard partial batch
      _fallback(canvas, c, r);
    }
  }

  // ---------------------------------------------------------------- helpers

  int _n(int base, [int min = 8]) =>
      math.max(min, (base * frame.detail * (compact ? .45 : 1)).round());

  void _glow(Canvas canvas, Offset at, double radius, Color color, double a) {
    if (radius <= 0) return;
    final alpha = (a * _gain).clamp(0.0, 1.0);
    _fill.shader = ui.Gradient.radial(at, radius, [
      color.withValues(alpha: alpha),
      color.withValues(alpha: alpha * .28),
      color.withValues(alpha: 0),
    ], const [0, .35, 1]);
    canvas.drawCircle(at, radius, _fill);
    _fill.shader = null;
  }

  void _stroke(Canvas canvas, Offset a, Offset b, Color col, double alpha,
      double width) {
    _line
      ..color = col.withValues(alpha: (alpha * _gain).clamp(0.0, 1.0))
      ..strokeWidth = width * _u;
    canvas.drawLine(a, b, _line);
  }

  void _path(Canvas canvas, Path p, Color col, double alpha, double width) {
    if (!compact && frame.detail > .45) {
      _line
        ..color = col.withValues(alpha: (alpha * .16 * _gain).clamp(0.0, 1.0))
        ..strokeWidth = width * _u * 4.5;
      canvas.drawPath(p, _line);
    }
    _line
      ..color = col.withValues(alpha: (alpha * _gain).clamp(0.0, 1.0))
      ..strokeWidth = width * _u;
    canvas.drawPath(p, _line);
  }

  void _star(Canvas canvas, double x, double y, double len, Color col,
      double alpha) {
    _stroke(canvas, Offset(x - len, y), Offset(x + len, y), col, alpha, .9);
    _stroke(canvas, Offset(x, y - len), Offset(x, y + len), col, alpha, .9);
    _stroke(canvas, Offset(x - len * .4, y - len * .4),
        Offset(x + len * .4, y + len * .4), Colors.white, alpha * .6, .6);
    _stroke(canvas, Offset(x - len * .4, y + len * .4),
        Offset(x + len * .4, y - len * .4), Colors.white, alpha * .6, .6);
  }

  void _bloom(Canvas canvas, Offset c, double r) {
    final breathe = .9 + .1 * math.sin(frame.t * 1.6);
    _glow(canvas, c, r * 1.9 * frame.spread, _pal[0], .22 * breathe);
    _glow(canvas, c, r * 1.2, _pal[2], .2 * breathe);
  }

  void _hotCore(Canvas canvas, Offset c, double r, double scale) {
    final pulse = 1 + .08 * math.sin(frame.t * 3.1) + frame.sound * .25;
    _glow(canvas, c, r * .85 * scale * pulse, _pal[0], .5);
    _glow(canvas, c, r * .42 * scale * pulse, _pal[1], .8);
    _glow(canvas, c, r * .2 * scale * pulse, Colors.white, 1.0);
    _glow(canvas, c, r * .08 * scale * pulse, Colors.white, 1.0);
  }

  void _fallback(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..shader = ui.Gradient.radial(c, r, [
        model.primary.withValues(alpha: .9),
        model.secondary.withValues(alpha: .3),
        Colors.transparent,
      ], const [0, .4, 1]);
    canvas.drawCircle(c, r, p);
  }

  // ------------------------------------------------------- 1 Neural Reactor

  static final Map<int, List<List<double>>> _sphereCache = {};
  static final Map<int, List<List<int>>> _neighbourCache = {};

  List<List<double>> _fibSphere(int n) => _sphereCache.putIfAbsent(n, () {
        final pts = <List<double>>[];
        final golden = math.pi * (3 - math.sqrt(5));
        for (var i = 0; i < n; i++) {
          final y = 1 - (i / (n - 1)) * 2;
          final rad = math.sqrt(1 - y * y);
          final th = golden * i;
          pts.add([math.cos(th) * rad, y, math.sin(th) * rad]);
        }
        return pts;
      });

  List<List<int>> _neighbours(int n) => _neighbourCache.putIfAbsent(n, () {
        final pts = _fibSphere(n);
        final out = <List<int>>[];
        for (var i = 0; i < n; i++) {
          final d = <(double, int)>[];
          for (var j = 0; j < n; j++) {
            if (i == j) continue;
            final dx = pts[i][0] - pts[j][0];
            final dy = pts[i][1] - pts[j][1];
            final dz = pts[i][2] - pts[j][2];
            d.add((dx * dx + dy * dy + dz * dz, j));
          }
          d.sort((a, b) => a.$1.compareTo(b.$1));
          out.add([for (final e in d.take(3)) e.$2]);
        }
        return out;
      });

  void _neuralReactor(Canvas canvas, Offset c, double r) {
    final f = frame;
    final n = _n(300, 60);
    final pts = _fibSphere(n);
    final nb = _neighbours(n);
    _pr.setup(c, r * f.spread, f.t * .32 + f.yaw, .38 * math.sin(f.t * .21) + f.pitch);
    final sx = List<double>.filled(n, 0), sy = List<double>.filled(n, 0);
    final sd = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final w = .86 + .05 * math.sin(f.t * 1.3 + i * .7) + f.sound * .08;
      _pr.p(pts[i][0] * w, pts[i][1] * w, pts[i][2] * w);
      sx[i] = _pr.x;
      sy[i] = _pr.y;
      sd[i] = _pr.depth;
    }
    final near = Path(), far = Path();
    for (var i = 0; i < n; i++) {
      for (final j in nb[i]) {
        if (j < i) continue;
        final target = (sd[i] + sd[j]) > 1.0 ? near : far;
        target
          ..moveTo(sx[i], sy[i])
          ..lineTo(sx[j], sy[j]);
      }
    }
    _path(canvas, far, _pal[2], .35, .8);
    _path(canvas, near, _pal[0], .75, 1.1);
    // Synapse pulses travelling across links.
    final pulses = _n(46, 12);
    for (var k = 0; k < pulses; k++) {
      final i = (_h(k, 3) * n).floor() % n;
      final j = nb[i][k % 3];
      final q = _frac(f.t * (.5 + _h(k, 4)) + _h(k, 5));
      final x = sx[i] + (sx[j] - sx[i]) * q, y = sy[i] + (sy[j] - sy[i]) * q;
      _dots.add(x, y, 1, .9, 3.4);
      if (k % 5 == 0) _glow(canvas, Offset(x, y), r * .07, _pal[1], .5);
    }
    for (var i = 0; i < n; i++) {
      _dots.add(sx[i], sy[i], i % 7 == 0 ? 1 : 0, .45 + .55 * sd[i], 1.4 + sd[i] * 2.8);
    }
    // Equatorial torus of light.
    final ring = _n(110, 30);
    _pr.setup(c, r * f.spread, -f.t * .9 + f.yaw, 1.15 + f.pitch);
    for (var k = 0; k < ring; k++) {
      final a = _tau * k / ring;
      final rr = .42 + .03 * math.sin(a * 6 + f.t * 4);
      _pr.p(math.cos(a) * rr, 0, math.sin(a) * rr);
      _dots.add(_pr.x, _pr.y, 2, .5 + .5 * _pr.depth, 2.2);
    }
    _hotCore(canvas, c, r, 1);
  }

  // ------------------------------------------------------- 2 Amber Hologram

  void _amberHologram(Canvas canvas, Offset c, double r) {
    final f = frame;
    final rings = _n(28, 10);
    const segs = 56;
    for (var k = 0; k < rings; k++) {
      final ta = (_h(k, 11) - .5) * math.pi;
      final tb = _h(k, 12) * math.pi + f.t * (_h(k, 13) - .5) * 1.1;
      final rad = (.5 + .5 * _h(k, 14)) * f.spread;
      final cta = math.cos(ta), sta = math.sin(ta);
      final ctb = math.cos(tb), stb = math.sin(tb);
      _pr.setup(c, r, f.t * .18 + f.yaw, .2 + f.pitch);
      final col = k % 3 == 0 ? _pal[1] : _pal[0];
      double? lx, ly;
      for (var s = 0; s <= segs; s++) {
        final u = _tau * s / segs;
        final bx = math.cos(u) * rad, by = math.sin(u) * rad;
        final y1 = by * cta, z1 = by * sta;
        final x2 = bx * ctb + z1 * stb, z2 = -bx * stb + z1 * ctb;
        _pr.p(x2, y1, z2);
        if (lx != null && _h(k * 97 + s, 15) > .3) {
          _stroke(canvas, Offset(lx, ly!), Offset(_pr.x, _pr.y), col,
              .18 + .55 * _pr.depth, .6 + _pr.depth * 1.1);
        }
        if (s % 9 == 0 && _h(k + s, 16) > .55) {
          _dots.add(_pr.x, _pr.y, 1, .6 + .4 * _pr.depth, 2.6);
        }
        lx = _pr.x;
        ly = _pr.y;
      }
    }
    // HUD notch ring and sunburst rays.
    final ticks = _n(120, 36);
    for (var k = 0; k < ticks; k++) {
      final a = _tau * k / ticks + f.t * .05;
      final len = k % 6 == 0 ? .1 : .04;
      final o1 = Offset(math.cos(a), math.sin(a));
      _stroke(canvas, c + o1 * r * 1.06, c + o1 * r * (1.06 + len), _pal[0],
          .35, .8);
    }
    final rays = _n(26, 10);
    for (var k = 0; k < rays; k++) {
      final a = _h(k, 17) * _tau + f.t * .03;
      final fl = .5 + .5 * math.sin(f.t * (2 + _h(k, 18) * 3) + k);
      final o = Offset(math.cos(a), math.sin(a));
      _stroke(canvas, c + o * r * .15, c + o * r * (.7 + .55 * fl), _pal[1],
          .12 + .2 * fl, .7);
    }
    // Inner fast filaments.
    for (var k = 0; k < 7; k++) {
      final rect = Rect.fromCenter(center: c, width: r * (.3 + k * .05),
          height: r * (.18 + k * .03));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(f.t * (1.4 + k * .3) * (k.isEven ? 1 : -1) + k);
      canvas.translate(-c.dx, -c.dy);
      _line
        ..color = _pal[1].withValues(alpha: (.55 * _gain).clamp(0.0, 1.0))
        ..strokeWidth = 1.1 * _u;
      canvas.drawOval(rect, _line);
      canvas.restore();
    }
    _hotCore(canvas, c, r, 1.05);
  }

  // --------------------------------------------------------- 3 Electric Web

  final List<Offset> _bolt = List.filled(33, Offset.zero);

  void _makeBolt(Offset a, Offset b, int seed, double rough) {
    _bolt[0] = a;
    _bolt[32] = b;
    var step = 32;
    var amp = (b - a).distance * rough;
    var salt = 0;
    while (step > 1) {
      final half = step ~/ 2;
      for (var i = half; i < 32; i += step) {
        final p0 = _bolt[i - half], p1 = _bolt[i + half];
        final mid = (p0 + p1) / 2;
        final d = p1 - p0;
        final len = d.distance;
        final nrm = len == 0 ? Offset.zero : Offset(-d.dy / len, d.dx / len);
        _bolt[i] = mid + nrm * ((_h(seed * 131 + i, 40 + salt) - .5) * amp);
      }
      amp *= .55;
      step = half;
      salt++;
    }
  }

  void _drawBolt(Canvas canvas, int from, int to, double alpha, double w) {
    final p = Path()..moveTo(_bolt[from].dx, _bolt[from].dy);
    for (var i = from + 1; i <= to; i++) {
      p.lineTo(_bolt[i].dx, _bolt[i].dy);
    }
    _path(canvas, p, _pal[0], .16 * alpha, 7 * w);
    _path(canvas, p, _pal[2], .4 * alpha, 3 * w);
    _path(canvas, p, Colors.white, .95 * alpha, 1.1 * w);
  }

  void _electricWeb(Canvas canvas, Offset c, double r) {
    final f = frame;
    final rr = r * f.spread;
    // Glass globe shell.
    _line
      ..color = _pal[0].withValues(alpha: (.35 * _gain).clamp(0.0, 1.0))
      ..strokeWidth = 1.4 * _u;
    canvas.drawCircle(c, rr, _line);
    _glow(canvas, c, rr * 1.02, _pal[0], .1);
    final bolts = _n(10, 4) + (f.state == AiraVisualState.processing ? 4 : 0);
    final epoch = (f.t * 8).floor();
    for (var k = 0; k < bolts; k++) {
      final seed = epoch * 17 + k * 97;
      final a = _h(seed, 1) * _tau + f.t * .2;
      final tip = c + Offset(math.cos(a), math.sin(a)) * rr * .98;
      _makeBolt(c, tip, seed, .22);
      final flick = .55 + .45 * _h(seed, 5);
      _drawBolt(canvas, 0, 32, flick, 1);
      // Fork.
      final at = 8 + (_h(seed, 6) * 12).floor();
      final base = _bolt[at];
      final fa = a + (_h(seed, 7) - .5) * 1.4;
      final fork = base + Offset(math.cos(fa), math.sin(fa)) * rr * .35;
      _makeBolt(base, fork, seed + 3, .3);
      _drawBolt(canvas, 0, 32, flick * .7, .6);
      _glow(canvas, tip, rr * .09, _pal[2], .7 * flick);
      _dots.add(tip.dx, tip.dy, 1, 1, 3.6);
    }
    // Outer web of nodes and flickering chords.
    final nodes = _n(18, 9);
    final pos = <Offset>[];
    for (var k = 0; k < nodes; k++) {
      final a = _tau * k / nodes + f.t * .07;
      final jr = rr * (1.16 + .06 * math.sin(f.t * 1.7 + k));
      pos.add(c + Offset(math.cos(a), math.sin(a)) * jr);
    }
    for (var k = 0; k < nodes; k++) {
      for (final step in const [1, 3, 5]) {
        final j = (k + step) % nodes;
        final fl = _h(epoch + k * 7 + step, 9);
        _stroke(canvas, pos[k], pos[j], _pal[step == 1 ? 0 : 2],
            step == 1 ? .45 : .12 + .25 * fl, step == 1 ? 1.1 : .6);
      }
      _dots.add(pos[k].dx, pos[k].dy, 1, .9, 3.2);
    }
    _hotCore(canvas, c, r, .9);
  }

  // ---------------------------------------------------------------- 4 AI Head

  static const List<double> _profile = [
    -.25, .98, -.30, .72, -.46, .46, -.56, .12, -.54, -.24, -.38, -.56,
    -.08, -.72, .24, -.67, .44, -.48, .52, -.22, .55, -.08, .50, .00,
    .56, .06, .70, .21, .58, .28, .61, .36, .55, .42, .58, .48, .50, .60,
    .37, .70, .20, .72, .14, .98,
  ];
  static List<double>? _outline, _interior, _brain;
  static List<List<int>>? _brainLinks;

  /// Chaikin-smoothed head silhouette (rounder skull, no boxy corners).
  static final List<double> _smooth = () {
    var pts = List<double>.of(_profile);
    for (var iter = 0; iter < 3; iter++) {
      final n = pts.length ~/ 2;
      final out = <double>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final x0 = pts[i * 2], y0 = pts[i * 2 + 1], x1 = pts[j * 2], y1 = pts[j * 2 + 1];
        out
          ..addAll([x0 * .75 + x1 * .25, y0 * .75 + y1 * .25])
          ..addAll([x0 * .25 + x1 * .75, y0 * .25 + y1 * .75]);
      }
      pts = out;
    }
    return pts;
  }();

  static bool _inside(double x, double y) {
    var inside = false;
    final p = _smooth;
    final n = p.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = p[i * 2], yi = p[i * 2 + 1], xj = p[j * 2], yj = p[j * 2 + 1];
      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static void _initHead() {
    if (_outline != null) return;
    final p = _smooth;
    final n = p.length ~/ 2;
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      for (var s = 0; s < 1; s++) {
        final q = s / 1;
        out
          ..add(p[i * 2] + (p[j * 2] - p[i * 2]) * q)
          ..add(p[i * 2 + 1] + (p[j * 2 + 1] - p[i * 2 + 1]) * q);
      }
    }
    final inner = <double>[], brain = <double>[];
    for (var k = 0; inner.length < 1300 && k < 9000; k++) {
      final x = _h(k, 21) * 1.4 - .65, y = _h(k, 22) * 1.8 - .8;
      if (!_inside(x, y)) continue;
      inner
        ..add(x)
        ..add(y);
      if (y < .05 && x < .42 && x > -.48 && brain.length < 96 && k % 3 == 0) {
        brain
          ..add(x)
          ..add(y);
      }
    }
    final links = <List<int>>[];
    final bn = brain.length ~/ 2;
    for (var i = 0; i < bn; i++) {
      final d = <(double, int)>[];
      for (var j = 0; j < bn; j++) {
        if (i == j) continue;
        final dx = brain[i * 2] - brain[j * 2], dy = brain[i * 2 + 1] - brain[j * 2 + 1];
        d.add((dx * dx + dy * dy, j));
      }
      d.sort((a, b) => a.$1.compareTo(b.$1));
      links.add([for (final e in d.take(3)) e.$2]);
    }
    _outline = out;
    _interior = inner;
    _brain = brain;
    _brainLinks = links;
  }

  void _aiHead(Canvas canvas, Offset c, double r) {
    _initHead();
    final f = frame;
    final rr = r * 1.05 * f.spread;
    final turn = math.cos(.38 * math.sin(f.t * .3) + f.yaw);
    final bob = math.sin(f.t * .8) * r * .02;
    Offset map(double x, double y) =>
        Offset(c.dx + x * rr * turn - rr * .04, c.dy + y * rr + bob);
    final scanY = -.75 + _frac(f.t * .22) * 1.8;
    final inner = _interior!;
    final step = compact ? 4 : (frame.detail > .7 ? 1 : 2);
    for (var i = 0; i < inner.length ~/ 2; i += step) {
      final x = inner[i * 2], y = inner[i * 2 + 1];
      final o = map(x, y);
      final shimmer = .5 + .5 * math.sin(f.t * 2 + i * .37);
      final near = (1 - ((y - scanY).abs() * 8)).clamp(0.0, 1.0);
      _dots.add(o.dx, o.dy, 0, .22 + .35 * shimmer + .5 * near, 1.2 + near * 1.6);
    }
    final out = _outline!;
    final on = out.length ~/ 2;
    for (var i = 0; i < on; i++) {
      final o = map(out[i * 2], out[i * 2 + 1]);
      final wave = .5 + .5 * math.sin(i * .25 - f.t * 3.2);
      _dots.add(o.dx, o.dy, wave > .8 ? 2 : 0, .45 + .55 * wave, 1.6 + wave * 1.6);
    }
    // Brain network with firing synapses.
    final brain = _brain!;
    final links = _brainLinks!;
    final bn = brain.length ~/ 2;
    _glow(canvas, map(-.08, -.3), rr * .5, _pal[1], .16);
    final net = Path();
    for (var i = 0; i < bn; i++) {
      final a = map(brain[i * 2], brain[i * 2 + 1]);
      for (final j in links[i]) {
        if (j < i) continue;
        final b = map(brain[j * 2], brain[j * 2 + 1]);
        net
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
    }
    _path(canvas, net, _pal[2], .5, .8);
    for (var i = 0; i < bn; i++) {
      final a = map(brain[i * 2], brain[i * 2 + 1]);
      final fire = math.pow(math.max(0, math.sin(f.t * (1.3 + _h(i, 23) * 2) + i)), 6)
          .toDouble();
      _dots.add(a.dx, a.dy, 1, .4 + .6 * fire, 2 + fire * 2.4);
      if (fire > .6) _glow(canvas, a, rr * .08, _pal[1], .6 * fire);
    }
    // Scan line.
    final sy = map(0, scanY).dy;
    _stroke(canvas, Offset(c.dx - rr * .7, sy), Offset(c.dx + rr * .8, sy),
        _pal[0], .35, 1.0);
    _glow(canvas, map(.5, -.02), rr * .06, Colors.white, .7); // eye
  }

  // ------------------------------------------------------------ 5 Jellyfish

  void _jellyfish(Canvas canvas, Offset c0, double r) {
    final f = frame;
    final c = c0.translate(0, math.sin(f.t * .9) * r * .07 - r * .18);
    final pulse = .5 + .5 * math.sin(f.t * 1.9);
    final rb = .66 * (1 - .13 * pulse) * f.spread;
    final hb = .48 * (1 + .16 * pulse);
    _glow(canvas, c.translate(0, -r * hb * .35), r * .75, _pal[0], .35);
    _glow(canvas, c.translate(0, -r * hb * .3), r * .3, Colors.white, .5);
    _pr.setup(c, r, f.t * .25 + f.yaw, .42 + f.pitch * .5);
    const lats = 9;
    final per = _n(44, 14);
    for (var j = 1; j <= lats; j++) {
      final phi = (j / lats) * math.pi / 2;
      final ringR = rb * math.sin(phi);
      final y = -hb * math.cos(phi);
      for (var k = 0; k < per; k++) {
        final u = _tau * k / per + j * .3;
        _pr.p(math.cos(u) * ringR, y, math.sin(u) * ringR);
        _dots.add(_pr.x, _pr.y, j == lats ? 1 : 0, .25 + .75 * _pr.depth,
            j == lats ? 2.6 : 1.4 + _pr.depth);
      }
    }
    // Meridians.
    for (var m = 0; m < 12; m++) {
      final u = _tau * m / 12;
      final path = Path();
      for (var j = 0; j <= 12; j++) {
        final phi = (j / 12) * math.pi / 2;
        _pr.p(math.cos(u) * rb * math.sin(phi), -hb * math.cos(phi),
            math.sin(u) * rb * math.sin(phi));
        j == 0 ? path.moveTo(_pr.x, _pr.y) : path.lineTo(_pr.x, _pr.y);
      }
      _path(canvas, path, _pal[0], .22, .7);
    }
    // Frilled rim.
    final rim = Path();
    for (var k = 0; k <= 96; k++) {
      final u = _tau * k / 96;
      final rr = rb * (1 + .05 * math.sin(u * 9 + f.t * 3));
      _pr.p(math.cos(u) * rr, .02 * math.sin(u * 9 - f.t * 3), math.sin(u) * rr);
      k == 0 ? rim.moveTo(_pr.x, _pr.y) : rim.lineTo(_pr.x, _pr.y);
    }
    _path(canvas, rim, _pal[1], .8, 1.8);
    // Tentacles.
    final tent = _n(16, 8);
    for (var k = 0; k < tent; k++) {
      final u = _tau * k / tent + .2;
      final len = 1.0 + .5 * _h(k, 31);
      double? lx, ly;
      for (var s = 0; s <= 24; s++) {
        final q = s / 24;
        final sway = .1 * math.sin(q * 6 - f.t * 2.4 + k) * q;
        _pr.p(math.cos(u) * rb * (1 - .35 * q) + sway, q * len,
            math.sin(u) * rb * (1 - .35 * q) + sway * .5);
        if (lx != null) {
          _stroke(canvas, Offset(lx, ly!), Offset(_pr.x, _pr.y),
              k.isEven ? _pal[0] : _pal[2], (.75 - q * .6) * (.4 + .6 * _pr.depth),
              2.2 - q * 1.6);
        }
        lx = _pr.x;
        ly = _pr.y;
      }
      _dots.add(lx!, ly!, 1, .7, 2.4);
    }
    // Oral arms.
    for (var k = 0; k < 4; k++) {
      final path = Path();
      for (var s = 0; s <= 20; s++) {
        final q = s / 20;
        _pr.p(.08 * math.cos(k * 1.6) + .12 * math.sin(q * 5 - f.t * 1.7 + k) * q,
            -hb * .2 + q * .95, .08 * math.sin(k * 1.6));
        s == 0 ? path.moveTo(_pr.x, _pr.y) : path.lineTo(_pr.x, _pr.y);
      }
      _path(canvas, path, _pal[1], .55, 3.2);
      _path(canvas, path, Colors.white, .4, 1);
    }
    // Marine snow.
    final snow = _n(70, 20);
    for (var k = 0; k < snow; k++) {
      final x = (_h(k, 33) - .5) * 3.2;
      final y = 1.4 - _frac(_h(k, 34) + f.t * .04) * 3.0;
      _dots.add(c0.dx + x * r, c0.dy + y * r, 2, .3 + .3 * _h(k, 35), 1.2);
    }
  }

  // -------------------------------------------------------- 6 Violet Vortex

  void _violetVortex(Canvas canvas, Offset c, double r) {
    final f = frame;
    _pr.setup(c, r * 1.05 * f.spread, f.t * .05 + f.yaw, 1.02 + f.pitch);
    final n = _n(950, 160);
    for (var k = 0; k < n; k++) {
      final arm = k % 3;
      final rad = .07 + 1.0 * math.pow(_h(k, 41), .7).toDouble();
      final base = arm * _tau / 3 + math.log(rad) * 2.3 +
          (_h(k, 42) - .5) * .55 / (rad + .3);
      final w = .9 / math.pow(rad + .22, 1.25);
      final a = base + f.t * w * .55;
      _pr.p(math.cos(a) * rad, (_h(k, 43) - .5) * .05, math.sin(a) * rad);
      final col = rad < .25 ? 1 : (k % 4 == 0 ? 2 : 0);
      final b = (1.15 - rad * .75) * (.5 + .5 * _pr.depth);
      _dots.add(_pr.x, _pr.y, col, b, rad < .3 ? 2.6 : 1.3 + _pr.depth * 1.2);
    }
    // Accretion ring.
    final ring = Path();
    for (var k = 0; k <= 80; k++) {
      final a = _tau * k / 80;
      _pr.p(math.cos(a) * .16, 0, math.sin(a) * .16);
      k == 0 ? ring.moveTo(_pr.x, _pr.y) : ring.lineTo(_pr.x, _pr.y);
    }
    _path(canvas, ring, _pal[1], .7, 4);
    _path(canvas, ring, Colors.white, .9, 1.4);
    // Polar jets, stronger when active.
    final jet = .25 + .6 * (f.energy - .6).clamp(0.0, .5) * 2;
    _pr.p(0, -1.1, 0);
    final top = Offset(_pr.x, _pr.y);
    _pr.p(0, 1.1, 0);
    final bot = Offset(_pr.x, _pr.y);
    _stroke(canvas, c, top, _pal[2], .35 * jet, 6);
    _stroke(canvas, c, top, Colors.white, .7 * jet, 1.2);
    _stroke(canvas, c, bot, _pal[2], .25 * jet, 5);
    _hotCore(canvas, c, r, .8);
  }

  // -------------------------------------------------------- 7 Aurora Ribbon

  void _auroraRibbon(Canvas canvas, Offset c, double r) {
    final f = frame;
    final ribbons = _n(6, 4);
    final samples = _n(110, 40);
    for (var k = 0; k < ribbons; k++) {
      final tiltX = (_h(k, 51) - .5) * 2.2;
      final tiltZ = (_h(k, 52) - .5) * 1.6;
      final rad = (.62 + .38 * _h(k, 53)) * f.spread;
      final ctx = math.cos(tiltX), stx = math.sin(tiltX);
      final ctz = math.cos(tiltZ), stz = math.sin(tiltZ);
      _pr.setup(c, r, f.t * (.25 + .15 * _h(k, 54)) * (k.isEven ? 1 : -1) + f.yaw,
          .3 + f.pitch);
      for (var strand = 0; strand < 6; strand++) {
        final off = (strand - 2.5) * .022;
        final path = Path();
        var depthSum = 0.0;
        for (var s = 0; s <= samples; s++) {
          final u = _tau * s / samples;
          final rr = rad * (1 + .13 * math.sin(3 * u + f.t * .8 + k)) + off;
          var x = math.cos(u) * rr;
          var y = .14 * math.sin(2 * u + f.t + k) + off * 2;
          var z = math.sin(u) * rr;
          final y1 = y * ctx - z * stx, z1 = y * stx + z * ctx;
          final x2 = x * ctz - y1 * stz, y2 = x * stz + y1 * ctz;
          x = x2;
          y = y2;
          z = z1;
          _pr.p(x, y, z);
          depthSum += _pr.depth;
          s == 0 ? path.moveTo(_pr.x, _pr.y) : path.lineTo(_pr.x, _pr.y);
        }
        final col = Color.lerp(_pal[k % 3], _pal[(k + 1) % 3], strand / 5)!;
        _path(canvas, path, col, .14 + .3 * depthSum / (samples + 1), 1.3);
      }
      // Comet head travelling along ribbon.
      final u = _frac(f.t * .12 + _h(k, 55)) * _tau;
      final rr = rad * (1 + .13 * math.sin(3 * u + f.t * .8 + k));
      final x = math.cos(u) * rr, y = .14 * math.sin(2 * u + f.t + k);
      final z = math.sin(u) * rr;
      final y1 = y * ctx - z * stx, z1 = y * stx + z * ctx;
      _pr.p(x * ctz - y1 * stz, x * stz + y1 * ctz, z1);
      _glow(canvas, Offset(_pr.x, _pr.y), r * .12, _pal[k % 3], .7);
      _dots.add(_pr.x, _pr.y, 1, 1, 3.6);
    }
    _hotCore(canvas, c, r, .85);
  }

  // ------------------------------------------------------------ 8 DNA Helix

  void _dnaHelix(Canvas canvas, Offset c, double r) {
    final f = frame;
    final n = _n(36, 18);
    const tz = .32;
    final ctz = math.cos(tz), stz = math.sin(tz);
    _pr.setup(c, r * f.spread, f.yaw, .18 + f.pitch);
    final ax = List<double>.filled(n, 0), ay = List<double>.filled(n, 0);
    final bx = List<double>.filled(n, 0), by = List<double>.filled(n, 0);
    final ad = List<double>.filled(n, 0), bd = List<double>.filled(n, 0);
    void proj(double x, double y, double z) =>
        _pr.p(x * ctz - y * stz, x * stz + y * ctz, z);
    for (var i = 0; i < n; i++) {
      final y = -.95 + 1.9 * i / (n - 1);
      final th = i * .42 + f.t * .9;
      const rad = .4;
      proj(math.cos(th) * rad, y, math.sin(th) * rad);
      ax[i] = _pr.x;
      ay[i] = _pr.y;
      ad[i] = _pr.depth;
      proj(math.cos(th + math.pi) * rad, y, math.sin(th + math.pi) * rad);
      bx[i] = _pr.x;
      by[i] = _pr.y;
      bd[i] = _pr.depth;
    }
    for (var i = 0; i < n; i++) {
      final m = Offset((ax[i] + bx[i]) / 2, (ay[i] + by[i]) / 2);
      final d = (ad[i] + bd[i]) / 2;
      _stroke(canvas, Offset(ax[i], ay[i]), m, i % 4 < 2 ? _pal[2] : _pal[0],
          .2 + .45 * d, 1.6);
      _stroke(canvas, m, Offset(bx[i], by[i]), i % 4 < 2 ? Colors.white : _pal[1],
          .2 + .45 * d, 1.6);
    }
    for (var i = 1; i < n; i++) {
      _stroke(canvas, Offset(ax[i - 1], ay[i - 1]), Offset(ax[i], ay[i]), _pal[0],
          .3 + .6 * ad[i], 1.2 + ad[i] * 2.2);
      _stroke(canvas, Offset(bx[i - 1], by[i - 1]), Offset(bx[i], by[i]), _pal[1],
          .3 + .6 * bd[i], 1.2 + bd[i] * 2.2);
    }
    for (var i = 0; i < n; i++) {
      _dots.add(ax[i], ay[i], 0, .5 + .5 * ad[i], 2 + ad[i] * 2);
      _dots.add(bx[i], by[i], 1, .5 + .5 * bd[i], 2 + bd[i] * 2);
    }
    // Spiral orbiters.
    final orb = _n(130, 30);
    for (var k = 0; k < orb; k++) {
      final y = -1.0 + _frac(_h(k, 61) + f.t * .07) * 2.0;
      final a = _h(k, 62) * _tau + f.t * 1.4;
      final rad = .6 + .25 * _h(k, 63);
      proj(math.cos(a) * rad, y, math.sin(a) * rad);
      _dots.add(_pr.x, _pr.y, 2, .3 + .5 * _pr.depth, 1.2);
    }
    _glow(canvas, c, r * .9, _pal[0], .14);
  }

  // -------------------------------------------------------- 9 Crystal Bloom

  void _crystalBloom(Canvas canvas, Offset c, double r) {
    final f = frame;
    final open = .5 + .5 * math.sin(f.t * .55);
    _pr.setup(c, r * f.spread, f.t * .14 + f.yaw, .5 + f.pitch);
    final layers = [
      (n: 12, len: 1.0, w: .2, lo: 1.15, hi: .18, rot: 0.0),
      (n: 9, len: .72, w: .17, lo: 1.3, hi: .5, rot: .35),
      (n: 6, len: .46, w: .13, lo: 1.45, hi: .9, rot: .7),
    ];
    for (var li = 0; li < layers.length; li++) {
      final L = layers[li];
      final e = L.lo + (L.hi - L.lo) * open;
      for (var k = 0; k < L.n; k++) {
        final phi = _tau * k / L.n + L.rot;
        final ce = math.cos(e), se = math.sin(e);
        final dx = math.cos(phi) * ce, dy = -se, dz = math.sin(phi) * ce;
        final sx = -math.sin(phi), sz = math.cos(phi);
        _pr.p(0, 0, 0);
        final o = Offset(_pr.x, _pr.y);
        _pr.p(dx * L.len, dy * L.len, dz * L.len);
        final tip = Offset(_pr.x, _pr.y);
        final td = _pr.depth;
        final m = L.len * .48;
        _pr.p(dx * m + sx * L.w, dy * m, dz * m + sz * L.w);
        final s1 = Offset(_pr.x, _pr.y);
        _pr.p(dx * m - sx * L.w, dy * m, dz * m - sz * L.w);
        final s2 = Offset(_pr.x, _pr.y);
        final shard = Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(s1.dx, s1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(s2.dx, s2.dy)
          ..close();
        final col = _pal[(k + li) % 3];
        _fill.color = col.withValues(alpha: ((.08 + .14 * td) * _gain).clamp(0.0, 1.0));
        canvas.drawPath(shard, _fill);
        _path(canvas, shard, Color.lerp(col, Colors.white, .45)!, .35 + .5 * td, 1.1);
        _stroke(canvas, o, tip, Colors.white, .2 + .4 * td, .7);
        final tw = math.pow(math.max(0, math.sin(f.t * 2.2 + k * 1.7 + li)), 10)
            .toDouble();
        _dots.add(tip.dx, tip.dy, 1, .5 + .5 * td, 2.6);
        if (tw > .3) _star(canvas, tip.dx, tip.dy, r * .09 * tw, col, tw);
      }
    }
    // Faceted gem core.
    final gem = Path();
    for (var k = 0; k <= 6; k++) {
      final a = _tau * k / 6 + f.t * .6;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * .14;
      k == 0 ? gem.moveTo(p.dx, p.dy) : gem.lineTo(p.dx, p.dy);
    }
    _hotCore(canvas, c, r, .75);
    _path(canvas, gem, Colors.white, .9, 1.4);
  }

  // ---------------------------------------------------------- 10 Solar Flare

  void _solarFlare(Canvas canvas, Offset c, double r) {
    final f = frame;
    final rs = r * .5 * f.spread * (1 + f.sound * .06);
    _glow(canvas, c, rs * 3.2, _pal[0], .3);
    _fill.shader = ui.Gradient.radial(c, rs * 1.04, [
      Colors.white.withValues(alpha: (_gain).clamp(0.0, 1.0)),
      _pal[1].withValues(alpha: (.95 * _gain).clamp(0.0, 1.0)),
      _pal[0].withValues(alpha: (.85 * _gain).clamp(0.0, 1.0)),
      _pal[2].withValues(alpha: 0),
    ], const [0, .45, .86, 1]);
    canvas.drawCircle(c, rs * 1.04, _fill);
    _fill.shader = null;
    // Rotating granulation on the visible hemisphere.
    _pr.setup(c, rs, f.t * .12 + f.yaw, .25 + f.pitch);
    final gran = _n(170, 40);
    for (var k = 0; k < gran; k++) {
      final lon = _h(k, 71) * _tau, lat = math.asin(_h(k, 72) * 2 - 1);
      _pr.p(math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon));
      if (_pr.depth < .5) continue;
      final fl = .5 + .5 * math.sin(f.t * 3 + k);
      _dots.add(_pr.x, _pr.y, fl > .7 ? 1 : 2, .2 + .4 * fl, 1.6);
    }
    // Corona rays.
    final rays = _n(96, 28);
    for (var k = 0; k < rays; k++) {
      final a = _h(k, 73) * _tau + f.t * .02;
      final len = rs * (.12 + .7 * _h(k, 74) * (.55 + .45 * math.sin(f.t * 1.6 + k)));
      final o = Offset(math.cos(a), math.sin(a));
      _stroke(canvas, c + o * rs * .98, c + o * (rs + len * .5), _pal[1], .5, 1.1);
      _stroke(canvas, c + o * (rs + len * .5), c + o * (rs + len), _pal[0], .22, .8);
    }
    // Magnetic flare loops with flowing plasma.
    for (var k = 0; k < 6; k++) {
      final a = _h(k, 75) * _tau + f.t * .03;
      final span = .16 + .12 * _h(k, 76);
      final grow = .5 + .5 * math.sin(f.t * .5 + k * 1.3);
      final p1 = c + Offset(math.cos(a - span), math.sin(a - span)) * rs;
      final p2 = c + Offset(math.cos(a + span), math.sin(a + span)) * rs;
      final ctrl = c + Offset(math.cos(a), math.sin(a)) * (rs + rs * (.5 + .9 * grow));
      final loop = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, p2.dx, p2.dy);
      _path(canvas, loop, _pal[0], .35, 5);
      _path(canvas, loop, _pal[1], .8, 1.6);
      for (var s = 0; s < 3; s++) {
        final q = _frac(f.t * .4 + s / 3 + k * .2);
        final x = (1 - q) * (1 - q) * p1.dx + 2 * (1 - q) * q * ctrl.dx + q * q * p2.dx;
        final y = (1 - q) * (1 - q) * p1.dy + 2 * (1 - q) * q * ctrl.dy + q * q * p2.dy;
        _dots.add(x, y, 1, 1, 3.4);
      }
    }
    // Ejecta.
    final ej = _n(70, 20);
    for (var k = 0; k < ej; k++) {
      final a = _h(k, 77) * _tau;
      final q = _frac(f.t * (.18 + .1 * _h(k, 78)) + _h(k, 79));
      final d = rs * (1.05 + q * 1.6);
      _dots.add(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d, k % 3 == 0 ? 1 : 0,
          (1 - q) * .9, 2.2 - q);
    }
    _glow(canvas, c, rs * .5, Colors.white, .8);
  }

  // ------------------------------------------------------- state overlays

  void _stateOverlay(Canvas canvas, Offset c, double r) {
    final f = frame;
    switch (f.state) {
      case AiraVisualState.idle:
        break;
      case AiraVisualState.listening:
        final n = _n(90, 24);
        for (var k = 0; k < n; k++) {
          final a = _h(k, 81) * _tau;
          final q = _frac(_h(k, 82) - f.clock * .55);
          final d = r * (1.0 + q * .75);
          _dots.add(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d, 0, q * .9, 1.8);
        }
        final amp = .04 + f.sound * .18;
        final ring = Path();
        for (var k = 0; k <= 120; k++) {
          final a = _tau * k / 120;
          final d = r * (1.28 + amp * math.sin(a * 14 + f.clock * 9));
          final p = c + Offset(math.cos(a), math.sin(a)) * d;
          k == 0 ? ring.moveTo(p.dx, p.dy) : ring.lineTo(p.dx, p.dy);
        }
        _path(canvas, ring, _pal[0], .6, 1.4);
      case AiraVisualState.thinking:
        for (var k = 0; k < 3; k++) {
          final rect = Rect.fromCircle(center: c, radius: r * (1.18 + k * .1));
          _line
            ..color = _pal[2].withValues(alpha: (.6 * _gain).clamp(0.0, 1.0))
            ..strokeWidth = (2.4 - k * .5) * _u;
          canvas.drawArc(rect, f.clock * (1.2 + k * .5) * (k.isEven ? 1 : -1),
              .9 - k * .2, false, _line);
        }
      case AiraVisualState.processing:
        const segs = 40;
        final rect = Rect.fromCircle(center: c, radius: r * 1.22);
        for (var k = 0; k < segs; k++) {
          if (_h(k, 83) < .3) continue;
          _line
            ..color = (k % 5 == 0 ? _pal[1] : _pal[0])
                .withValues(alpha: (.7 * _gain).clamp(0.0, 1.0))
            ..strokeWidth = 3 * _u;
          canvas.drawArc(rect, _tau * k / segs + f.clock * 2.2, _tau / segs * .6,
              false, _line);
        }
        final sweep = _frac(f.clock * .5) * _tau;
        _line
          ..color = Colors.white.withValues(alpha: (.8 * _gain).clamp(0.0, 1.0))
          ..strokeWidth = 1.2 * _u;
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.32), -math.pi / 2,
            sweep, false, _line);
      case AiraVisualState.completed:
        final q = (f.stateAge / 1.6).clamp(0.0, 1.0);
        _line
          ..color = const Color(0xFFB8FF8A)
              .withValues(alpha: ((1 - q) * .9 * _gain).clamp(0.0, 1.0))
          ..strokeWidth = (4 - q * 3) * _u;
        canvas.drawCircle(c, r * (.6 + q * 1.1), _line);
        _glow(canvas, c, r * (.4 + q * .8), const Color(0xFFFFE89A), (1 - q) * .45);
      case AiraVisualState.speaking:
        for (var k = 0; k < 4; k++) {
          final q = _frac(f.clock * .7 + k / 4);
          final amp = .7 + .3 * math.sin(f.clock * 11 + k) + f.sound * .4;
          _line
            ..color = _pal[k.isEven ? 0 : 1]
                .withValues(alpha: ((1 - q) * .55 * amp * _gain).clamp(0.0, 1.0))
            ..strokeWidth = 2 * _u;
          canvas.drawCircle(c, r * (1.0 + q * .7), _line);
        }
    }
    if (f.tapAge < 1.2) {
      final q = f.tapAge / 1.2;
      _line
        ..color = Colors.white.withValues(alpha: ((1 - q) * .8).clamp(0.0, 1.0))
        ..strokeWidth = 2 * _u;
      canvas.drawCircle(c, r * (.3 + q * 1.4), _line);
      final n = _n(40, 14);
      for (var k = 0; k < n; k++) {
        final a = _tau * k / n;
        final d = r * (.2 + q * 1.5 * (.6 + .4 * _h(k, 84)));
        _dots.add(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d, 1, 1 - q, 2.8);
      }
    }
  }

  void _glitter(Canvas canvas, Offset c, double r) {
    final f = frame;
    final n = _n(64, 16);
    for (var k = 0; k < n; k++) {
      final a = _h(k, 91) * _tau;
      final d = r * (.25 + 1.45 * math.sqrt(_h(k, 92)));
      final tw = math.pow(math.max(0, math.sin(f.clock * (1.4 + _h(k, 93) * 2.6) + k * 2.1)), 8)
          .toDouble();
      final x = c.dx + math.cos(a) * d, y = c.dy + math.sin(a) * d;
      _dots.add(x, y, k % 3, .25 + .75 * tw, 1.2 + tw * 1.8);
      if (tw > .72 && !compact) _star(canvas, x, y, 6 * _u * tw, _pal[k % 3], tw);
    }
  }

  @override
  bool shouldRepaint(covariant AiraCorePainter old) =>
      old.model != model || old.frame != frame || old.compact != compact;
}
