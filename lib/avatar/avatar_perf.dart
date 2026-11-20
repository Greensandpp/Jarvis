import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Snapshot of avatar rendering performance.
class AvatarPerfSnapshot {
  const AvatarPerfSnapshot({
    required this.fps,
    required this.cpuP50Ms,
    required this.cpuP95Ms,
    required this.buildP95Ms,
    required this.rasterP95Ms,
    required this.triangles,
    required this.particles,
    required this.frames,
  });
  final double fps;
  final double cpuP50Ms; // scene update + draw-list build + canvas recording
  final double cpuP95Ms;
  final double buildP95Ms; // Flutter UI thread (FrameTiming)
  final double rasterP95Ms; // Flutter raster thread (FrameTiming)
  final int triangles;
  final int particles;
  final int frames;

  String get line => 'fps=${fps.toStringAsFixed(1)} cpu_p50=${cpuP50Ms.toStringAsFixed(2)}ms '
      'cpu_p95=${cpuP95Ms.toStringAsFixed(2)}ms ui_p95=${buildP95Ms.toStringAsFixed(2)}ms '
      'raster_p95=${rasterP95Ms.toStringAsFixed(2)}ms tris=$triangles particles=$particles frames=$frames';
}

/// Rolling performance monitor. Logs one `SERPENT_PERF` line every
/// [logEvery] so CI emulator runs and the owner's phone (adb logcat) can
/// report real numbers without any UI.
class AvatarPerfMonitor {
  AvatarPerfMonitor({this.logEvery = const Duration(seconds: 5), this.tag = 'SERPENT_PERF'});

  final Duration logEvery;
  final String tag;
  static AvatarPerfSnapshot? latest;

  final List<double> _cpu = [];
  final List<double> _ui = [];
  final List<double> _raster = [];
  final List<double> _intervals = [];
  Duration? _lastTick;
  Duration _sinceLog = Duration.zero;
  int _frames = 0;
  int _tris = 0, _parts = 0;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _push(_ui, t.buildDuration.inMicroseconds / 1000);
      _push(_raster, t.rasterDuration.inMicroseconds / 1000);
    }
  }

  static void _push(List<double> l, double v) {
    l.add(v);
    if (l.length > 240) l.removeAt(0);
  }

  void onTick(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    final dt = elapsed - last;
    _sinceLog += dt;
    if (_sinceLog >= logEvery) {
      _sinceLog = Duration.zero;
      final s = snapshot();
      latest = s;
      debugPrint('$tag ${s.line}');
    }
  }

  final Stopwatch _clock = Stopwatch()..start();
  int? _lastFrameUs;

  /// Called after each painted frame; fps is measured between painted
  /// frames (so the Battery 30 fps cap shows up as ~30).
  void onFrameBuilt(Duration cpu, int triangles, int particles) {
    final now = _clock.elapsedMicroseconds;
    final prev = _lastFrameUs;
    _lastFrameUs = now;
    if (prev != null && now - prev < 500000) _push(_intervals, (now - prev) / 1000);
    _frames++;
    _tris = triangles;
    _parts = particles;
    _push(_cpu, cpu.inMicroseconds / 1000);
  }

  static double _pct(List<double> l, double p) {
    if (l.isEmpty) return 0;
    final s = [...l]..sort();
    return s[math.min(s.length - 1, (p * (s.length - 1)).round())];
  }

  AvatarPerfSnapshot snapshot() {
    final meanInterval = _intervals.isEmpty ? 0.0 : _intervals.reduce((a, b) => a + b) / _intervals.length;
    return AvatarPerfSnapshot(
      fps: meanInterval > 0 ? 1000 / meanInterval : 0,
      cpuP50Ms: _pct(_cpu, 0.5),
      cpuP95Ms: _pct(_cpu, 0.95),
      buildP95Ms: _pct(_ui, 0.95),
      rasterP95Ms: _pct(_raster, 0.95),
      triangles: _tris,
      particles: _parts,
      frames: _frames,
    );
  }
}
