import 'dart:math' as math;

/// Minimal immutable 3D vector used by the procedural avatar engine.
///
/// Pure Dart (no Flutter import) so the rig, state machine and viseme logic
/// can be unit tested and later reused by a GPU renderer (Filament) backend.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 1, 0);
  static const forward = Vec3(0, 0, 1);
  static const right = Vec3(1, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final l = length;
    if (l < 1e-9) return Vec3.up;
    return Vec3(x / l, y / l, z / l);
  }

  Vec3 lerp(Vec3 o, double t) => Vec3(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  /// Rotates this vector around [axis] (unit) by [angle] radians (Rodrigues).
  Vec3 rotate(Vec3 axis, double angle) {
    final c = math.cos(angle), s = math.sin(angle);
    return this * c + axis.cross(this) * s + axis * (axis.dot(this) * (1 - c));
  }

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Centripetal-free uniform Catmull-Rom interpolation between p1 and p2.
Vec3 catmullRom(Vec3 p0, Vec3 p1, Vec3 p2, Vec3 p3, double t) {
  final t2 = t * t, t3 = t2 * t;
  double c(double a, double b, double cc, double d) =>
      0.5 * ((2 * b) + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3);
  return Vec3(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y), c(p0.z, p1.z, p2.z, p3.z));
}

/// Samples a Catmull-Rom spline through [points] into [count] evenly spaced
/// (by parameter) positions. End points are duplicated as phantom controls.
List<Vec3> sampleSpline(List<Vec3> points, int count) {
  assert(points.length >= 2 && count >= 2);
  final n = points.length;
  final out = <Vec3>[];
  for (var i = 0; i < count; i++) {
    final u = i / (count - 1) * (n - 1);
    var seg = u.floor();
    if (seg >= n - 1) seg = n - 2;
    final t = u - seg;
    final p0 = points[seg == 0 ? 0 : seg - 1];
    final p1 = points[seg];
    final p2 = points[seg + 1];
    final p3 = points[seg + 2 >= n ? n - 1 : seg + 2];
    out.add(catmullRom(p0, p1, p2, p3, t));
  }
  return out;
}

/// Orthonormal frame along a curve (parallel transport, no flips).
class CurveFrame {
  const CurveFrame(this.position, this.tangent, this.normal, this.binormal);
  final Vec3 position;
  final Vec3 tangent;
  final Vec3 normal;
  final Vec3 binormal;
}

List<CurveFrame> parallelTransportFrames(List<Vec3> pts, {Vec3 seedNormal = Vec3.up}) {
  final n = pts.length;
  final tangents = <Vec3>[
    for (var i = 0; i < n; i++)
      (pts[i + 1 < n ? i + 1 : i] - pts[i - 1 >= 0 ? i - 1 : i]).normalized(),
  ];
  var normal = seedNormal - tangents[0] * seedNormal.dot(tangents[0]);
  if (normal.length < 1e-4) normal = Vec3.right - tangents[0] * Vec3.right.dot(tangents[0]);
  normal = normal.normalized();
  final frames = <CurveFrame>[];
  for (var i = 0; i < n; i++) {
    if (i > 0) {
      final axis = tangents[i - 1].cross(tangents[i]);
      final s = axis.length;
      if (s > 1e-6) {
        final angle = math.atan2(s, tangents[i - 1].dot(tangents[i]));
        normal = normal.rotate(axis * (1 / s), angle);
      }
      // Re-orthogonalise against drift.
      normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized();
    }
    frames.add(CurveFrame(pts[i], tangents[i], normal, tangents[i].cross(normal)));
  }
  return frames;
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Smooth Hermite ramp of [x] between [a] and [b].
double smoothstep(double a, double b, double x) {
  if (b == a) return x < a ? 0 : 1;
  final t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double lerpD(double a, double b, double t) => a + (b - a) * t;

/// Exponential approach factor for frame-rate independent smoothing.
double approach(double dt, double halfLife) =>
    halfLife <= 0 ? 1 : 1 - math.pow(0.5, dt / halfLife).toDouble();

/// Deterministic hash noise in [0,1) for repeatable procedural effects.
double hash01(int n) {
  var x = (n * 0x27d4eb2d) & 0x7fffffff;
  x = (x ^ (x >> 15)) * 0x2c1b3c6d & 0x7fffffff;
  x = (x ^ (x >> 12)) * 0x297a2d39 & 0x7fffffff;
  x ^= x >> 15;
  return (x & 0xffffff) / 0x1000000;
}

/// Simple perspective camera: world (y up, +z towards viewer) to screen.
class PerspectiveCamera {
  PerspectiveCamera({
    required this.width,
    required this.height,
    this.distance = 3.4,
    this.fovY = 0.92,
    this.target = Vec3.zero,
    this.yaw = 0,
    this.pitch = 0,
  });

  final double width;
  final double height;
  final double distance;
  final double fovY;
  final Vec3 target;
  final double yaw;
  final double pitch;

  late final double _f = (height / 2) / math.tan(fovY / 2);
  late final double _cy = math.cos(yaw), _sy = math.sin(yaw);
  late final double _cp = math.cos(pitch), _sp = math.sin(pitch);

  /// View-space position (camera looks down -z; larger z = closer).
  Vec3 toView(Vec3 p) {
    final q = p - target;
    final x1 = q.x * _cy + q.z * _sy;
    final z1 = -q.x * _sy + q.z * _cy;
    final y2 = q.y * _cp - z1 * _sp;
    final z2 = q.y * _sp + z1 * _cp;
    return Vec3(x1, y2, z2 - distance);
  }

  /// Returns (sx, sy, depth, scale). depth > 0 means in front of camera.
  ({double x, double y, double depth, double scale}) project(Vec3 p) {
    final v = toView(p);
    final depth = -v.z;
    final d = depth < 0.05 ? 0.05 : depth;
    final s = _f / d;
    return (x: width / 2 + v.x * s, y: height / 2 - v.y * s, depth: depth, scale: s);
  }

  /// Direction from a world point towards the camera eye.
  Vec3 viewDirFrom(Vec3 p) {
    final eye = Vec3(-_sy * distance * _cp, distance * _sp, _cy * distance * _cp) + target;
    return (eye - p).normalized();
  }
}
