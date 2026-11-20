import 'dart:typed_data';
import 'dart:ui' as ui;

// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'core/avatar_scene.dart';
import 'core/render_list.dart';

/// Thin Canvas backend for [RenderList]. All geometry, shading and depth
/// ordering already happened in pure Dart ([AvatarScene]).
class SerpentGuardianPainter extends CustomPainter {
  SerpentGuardianPainter({required this.scene, required this.sprite, required this.onBuilt, super.repaint});

  final AvatarScene scene;
  final ui.Image? Function() sprite;
  final void Function(RenderList list, Duration cpu) onBuilt;

  static final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final sw = Stopwatch()..start();
    final list = scene.build(size.width, size.height);
    if (list.background) _background(canvas, size, list);
    final blurOk = list.allowBlur;
    final img = sprite();
    for (final op in list.ops) {
      switch (op) {
        case TriOp():
          final v = ui.Vertices.raw(ui.VertexMode.triangles, op.positions, colors: op.colors, indices: op.indices);
          _paint
            ..shader = null
            ..maskFilter = null
            ..style = PaintingStyle.fill
            ..color = const Color(0xFFFFFFFF)
            ..blendMode = op.additive ? BlendMode.plus : BlendMode.srcOver;
          canvas.drawVertices(v, BlendMode.dst, _paint);
          v.dispose();
        case LineOp():
          if (op.blur > 0 && !blurOk) break;
          final p = Paint()
            ..color = Color(op.color)
            ..strokeWidth = op.width
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke
            ..blendMode = op.additive ? BlendMode.plus : BlendMode.srcOver;
          if (op.blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, op.blur);
          canvas.drawRawPoints(op.mode == LineMode.pairs ? ui.PointMode.lines : ui.PointMode.polygon, op.points, p);
        case GlowOp():
          if (op.radius <= 0.5) break;
          final c = Offset(op.x, op.y);
          final base = Color(op.color);
          final p = Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(c, op.radius, [base, base.withValues(alpha: 0.35), base.withValues(alpha: 0)],
                const [0.0, 0.35, 1.0]);
          canvas.drawCircle(c, op.radius, p);
          if (op.core > 0) {
            final r = op.radius * 0.28;
            final core = Color.fromARGB(_byte(op.core), 255, 255, 255);
            canvas.drawCircle(
                c,
                r,
                Paint()
                  ..blendMode = BlendMode.plus
                  ..shader = ui.Gradient.radial(c, r, [core, core.withValues(alpha: 0)]));
          }
        case SpriteOp():
          _sprites(canvas, op, img);
        case PolyOp():
          if (op.points.length < 6) break;
          final path = Path()..moveTo(op.points[0], op.points[1]);
          for (var i = 2; i < op.points.length; i += 2) {
            path.lineTo(op.points[i], op.points[i + 1]);
          }
          path.close();
          canvas.drawPath(
              path,
              Paint()
                ..color = Color(op.color)
                ..blendMode = op.additive ? BlendMode.plus : BlendMode.srcOver);
      }
    }
    sw.stop();
    onBuilt(list, sw.elapsed);
  }

  void _background(Canvas canvas, Size size, RenderList list) {
    final rect = Offset.zero & size;
    final tint = Color(list.backgroundTint);
    final k = 0.1 + 0.12 * list.backgroundPower;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(Offset(size.width / 2, size.height * 0.55), size.longestSide * 0.7,
              [Color.lerp(Colors.black, tint, k)!, const Color(0xFF02060A), Colors.black], const [0.0, 0.55, 1.0]));
    // Faint vertical light bars (sci-fi chamber, like the reference).
    final bar = Paint()..blendMode = BlendMode.plus;
    for (final fx in const [0.04, 0.14, 0.86, 0.96]) {
      final x = size.width * fx;
      bar.shader = ui.Gradient.linear(Offset(x, size.height * 0.15), Offset(x, size.height * 0.85), [
        tint.withValues(alpha: 0),
        tint.withValues(alpha: 0.10 * list.backgroundPower),
        tint.withValues(alpha: 0),
      ]);
      canvas.drawRect(Rect.fromLTWH(x - 1.5, size.height * 0.15, 3, size.height * 0.7), bar);
    }
  }

  void _sprites(Canvas canvas, SpriteOp op, ui.Image? img) {
    final n = op.count;
    if (img == null) {
      final p = Paint()..blendMode = BlendMode.plus;
      for (var i = 0; i < n; i++) {
        p.color = Color(op.colors[i]);
        canvas.drawCircle(Offset(op.data[i * 3], op.data[i * 3 + 1]), op.data[i * 3 + 2], p);
      }
      return;
    }
    final half = img.width / 2;
    final xf = Float32List(n * 4);
    final rects = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      final s = op.data[i * 3 + 2] / half * 2.2; // sprite glow is wider than the core dot
      xf[i * 4] = s;
      xf[i * 4 + 1] = 0;
      xf[i * 4 + 2] = op.data[i * 3] - half * s;
      xf[i * 4 + 3] = op.data[i * 3 + 1] - half * s;
      rects[i * 4] = 0;
      rects[i * 4 + 1] = 0;
      rects[i * 4 + 2] = img.width.toDouble();
      rects[i * 4 + 3] = img.height.toDouble();
    }
    canvas.drawRawAtlas(img, xf, rects, op.colors, BlendMode.modulate, null, Paint()..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(covariant SerpentGuardianPainter oldDelegate) => oldDelegate.scene != scene;
}

int _byte(double v) {
  final i = (v * 255).round();
  return i < 0 ? 0 : (i > 255 ? 255 : i);
}

/// Soft white radial sprite used for every particle (tinted per particle).
ui.Image? buildGlowSprite() {
  try {
    const s = 64.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawCircle(
        const Offset(s / 2, s / 2),
        s / 2,
        Paint()
          ..shader = ui.Gradient.radial(const Offset(s / 2, s / 2), s / 2,
              const [Color(0xFFFFFFFF), Color(0x88FFFFFF), Color(0x00FFFFFF)], const [0.0, 0.22, 1.0]));
    return rec.endRecording().toImageSync(64, 64);
  } catch (_) {
    return null;
  }
}
