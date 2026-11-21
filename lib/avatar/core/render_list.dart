import 'dart:typed_data';

/// Renderer-neutral draw list produced by [AvatarScene] every frame.
///
/// Everything is already projected to screen pixels and shaded, so the
/// Flutter painter is a thin loop over these ops. A GPU backend (Filament)
/// would instead consume the rigs directly; this list is only for the
/// procedural Canvas renderer.
sealed class RenderOp {
  const RenderOp();
}

/// Indexed triangles with per-vertex ARGB colours.
class TriOp extends RenderOp {
  TriOp(this.positions, this.colors, this.indices, {required this.additive});
  final Float32List positions; // x,y pairs
  final Int32List colors; // ARGB per vertex
  final Uint16List indices;
  final bool additive;
  int get triangles => indices.length ~/ 3;
}

enum LineMode { strip, pairs }

/// A polyline (strip) or independent segments (pairs), single colour.
class LineOp extends RenderOp {
  LineOp(this.points, this.color, this.width, {this.mode = LineMode.strip, this.additive = true, this.blur = 0});
  final Float32List points; // x,y pairs
  final int color;
  final double width;
  final LineMode mode;
  final bool additive;
  final double blur; // 0 = sharp; >0 = soft glow (skipped in battery mode)
}

/// Soft radial glow spot (bloom substitute).
class GlowOp extends RenderOp {
  const GlowOp(this.x, this.y, this.radius, this.color, {this.core = 0});
  final double x;
  final double y;
  final double radius;
  final int color;
  final double core; // 0..1 white-hot centre amount
}

/// Glowing particle sprites.
class SpriteOp extends RenderOp {
  SpriteOp(this.data, this.colors);
  final Float32List data; // x, y, size triples
  final Int32List colors;
  int get count => colors.length;
}

/// Filled convex polygon (e.g. lip shape, hologram panels).
class PolyOp extends RenderOp {
  PolyOp(this.points, this.color, {this.additive = false});
  final Float32List points;
  final int color;
  final bool additive;
}

class RenderList {
  final List<RenderOp> ops = [];
  bool background = true;
  double backgroundPower = 1;
  int backgroundTint = 0xFF00E8A2;
  bool allowBlur = true;
  int triangleCount = 0;
  int particleCount = 0;

  void add(RenderOp op) {
    ops.add(op);
    if (op is TriOp) triangleCount += op.triangles;
    if (op is SpriteOp) particleCount += op.count;
  }
}

/// Packs a colour from float channels (0..1) and alpha (0..1).
int packArgb(double r, double g, double b, [double a = 1]) {
  int c(double v) {
    final i = (v * 255).round();
    return i < 0 ? 0 : (i > 255 ? 255 : i);
  }

  return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
}

double chR(int argb) => ((argb >> 16) & 0xFF) / 255.0;
double chG(int argb) => ((argb >> 8) & 0xFF) / 255.0;
double chB(int argb) => (argb & 0xFF) / 255.0;

/// Scales the RGB of [argb] by [k] (for additive brightness), alpha kept.
int scaleRgb(int argb, double k, [double alpha = 1]) =>
    packArgb(chR(argb) * k, chG(argb) * k, chB(argb) * k, alpha);

int mixArgb(int a, int b, double t, [double alpha = 1]) => packArgb(
      chR(a) + (chR(b) - chR(a)) * t,
      chG(a) + (chG(b) - chG(a)) * t,
      chB(a) + (chB(b) - chB(a)) * t,
      alpha,
    );
